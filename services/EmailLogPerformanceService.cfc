/**
 * A service to abstract logic for dealing with
 * summary statistic logging for email templates
 *
 * @singleton      true
 * @presideService true
 */
component {

	property name="sqlRunner"       inject="sqlRunner";
	property name="timeSeriesUtils" inject="emailLogPerformanceTimeSeriesUtils";

	property name="templateDao"          inject="presidecms:object:email_template";
	property name="statsSummaryDao"      inject="presidecms:object:email_template_stats";
	property name="clickStatsSummaryDao" inject="presidecms:object:email_template_click_stats";
	property name="activityDao"          inject="presidecms:object:email_template_send_log_activity";

// CONSTRUCTOR
	public any function init() {
		return this;
	}

// PUBLIC API METHODS
	public any function recordHit(
		  required string  emailTemplateId
		, required date    hitDate
		, required string  hitStat
		,          struct  data       = {}
		,          numeric hitCount   = 1
		,          boolean uniqueOpen = false
	) {
		sqlRunner.runSql(
			  dsn        = _getDsn()
			, sql        = _getRecordHitSql( arguments.hitStat )
			, params     = _prepareHitRecordParams( argumentCollection=arguments )
			, returnType = "info"
		);

		if ( arguments.hitStat == "click" ) {
			_recordClick(
				  argumentCollection = arguments.data
				, emailTemplateId    = arguments.emailTemplateId
				, hitDate            = arguments.hitDate
				, clicCount          = arguments.hitCount
			);
		}
		if ( arguments.hitStat == "open" && arguments.uniqueOpen ) {
			recordHit( argumentCollection=arguments, hitCount=1, hitStat="unique_open" );
		}
	}

	public numeric function getStatCount(
		  required string templateId
		, required string field
		,          any    dateFrom = ""
		,          any    dateTo   = ""
	) {
		return Val( statsSummaryDao.selectData(
			  selectFields = [ "sum( #_validateStatField( arguments.field )# ) as stat_count" ]
			, filter       = { template=arguments.templateId }
			, extraFilters = _getEmailLogPerformanceDateFilters( argumentCollection=arguments )
		).stat_count );
	}


	public struct function getStats(
		  required string  templateId
		, required string  dateFrom
		, required string  dateTo
		,          numeric timePoints = 1
		,          boolean uniqueOpens = ( arguments.timePoints == 1 )
	) {
		var timeResolution  = timeSeriesUtils.calculateTimeResolution( arguments.dateFrom, arguments.dateTo, "h" );
		var dates           = timeSeriesUtils.getExpectedTimes( timeResolution, arguments.dateFrom, arguments.dateTo );
		var commonArgs      = {
			  timeResolution    = timeResolution
			, expectedTimes     = dates
			, sourceObject      = "email_template_stats"
			, startDate         = arguments.dateFrom
			, endDate           = arguments.dateTo
			, valuesOnly        = true
			, aggregateFunction = "sum"
			, timeField         = "hour_start"
			, timeFieldIsEpoch  = true
			, epochResolution   = "h"
			, minResolution     = "h"
			, extraFilters      = [ { filter={ template=arguments.templateId } } ]
		};

		var stats = {
			  sent      = timeSeriesUtils.getTimeSeriesData( argumentCollection=commonArgs, aggregateOver="send_count"     )
			, delivered = timeSeriesUtils.getTimeSeriesData( argumentCollection=commonArgs, aggregateOver="delivery_count" )
			, failed    = timeSeriesUtils.getTimeSeriesData( argumentCollection=commonArgs, aggregateOver="fail_count"     )
			, opened    = timeSeriesUtils.getTimeSeriesData( argumentCollection=commonArgs, aggregateOver="open_count"     )
			, clicks    = timeSeriesUtils.getTimeSeriesData( argumentCollection=commonArgs, aggregateOver="click_count"    )
			, dates     = dates
		};

		for( var i=1; i <= ArrayLen( stats.dates ); i++ ) {
			stats.dates[ i ] = DateTimeFormat( stats.dates[ i ], "yyyy-mm-dd HH:nn" );
		}

		return stats;
	}

	public struct function getLinkClickStats(
		  required string templateId
		,          string dateFrom = ""
		,          string dateTo   = ""
	) {
		var extraFilters  = _getEmailLogPerformanceDateFilters( argumentCollection=arguments );
		var clickStats    = StructNew( "ordered" );
		var rawClickStats = clickStatsSummaryDao.selectData(
			  filter       = { template=arguments.templateId }
			, selectFields = [ "sum( click_count ) as summed_count", "link_hash", "link", "link_title", "link_body" ]
			, extraFilters = extraFilters
			, groupBy      = "link_hash"
			, orderBy      = "summed_count desc"
		);

		for( var link in rawClickStats ) {
			if ( !StructKeyExists( clickStats, link.link_body ) ) {
				clickStats[ link.link_body ] = {
					  links      = []
					, totalCount = 0
				};
			}

			ArrayAppend( clickStats[ link.link_body ].links, {
				  link       = link.link
				, title      = link.link_title
				, body       = link.link_body
				, clickCount = link.summed_count
			} );

			clickStats[ link.link_body ].totalCount += link.summed_count;
		}

		return clickStats;
	}

	public function getFirstStatDate( required string templateId ) {
		var earliest = statsSummaryDao.selectData(
			  selectFields = [ "min( hour_start ) as first_hour" ]
			, filter       = { template=arguments.templateId }
		);

		if ( earliest.recordCount && Val( earliest.first_hour ) ) {
			return DateAdd( "h", earliest.first_hour, "1970-01-01" );
		}

		return "";
	}

	public function getLastStatDate( required string templateId ) {
		var latest = statsSummaryDao.selectData(
			  selectFields = [ "max( hour_start ) as last_hour" ]
			, filter = { template=arguments.templateId }
		);

		if ( latest.recordCount && Val( latest.last_hour ) ) {
			return DateAdd( "h", latest.last_hour+1, "1970-01-01" );
		}

		return "";
	}

	public void function migrateToSummaryTables() {
		var emailTemplate = "";
		do {
			emailTemplate = templateDao.selectData(
				  selectFields       = [ "id" ]
				, filter             = "stats_collection_enabled is null or stats_collection_enabled = :stats_collection_enabled"
				, filterParams       = { stats_collection_enabled=false }
				, maxrows            = 1
				, orderBy            = "datecreated desc"
				, useCache           = false
				, allowDraftVersions = true
			);

			if ( emailTemplate.recordCount ) {
				_migrateTemplateToSummaryTables( emailTemplate.id );
			}
		} while ( emailTemplate.recordCount )
	}

// PRIVATE HELPERS
	private any function _recordClick(
		  required string  emailTemplateId
		, required date    hitDate
		,          string  link       = ""
		,          string  link_body  = ""
		,          string  link_title = ""
		,          numeric clickCount = 1
	) {
		if ( !Len( arguments.link ) ) {
			return;
		}

		sqlRunner.runSql(
			  dsn        = _getDsn()
			, sql        = _getRecordClickSql()
			, params     = _prepareClickRecordParams( argumentCollection=arguments )
			, returnType = "info"
		);
	}

	private string function _getDsn() {
		if ( !StructKeyExists( variables, "_dsn" ) ) {
			variables._dsn = $getPresideObject( "email_template_stats" ).getDsn();
		}

		return variables._dsn;
	}

	private string function _getRecordHitSql( hitStat ) {
		var po        = $getPresideObject( "email_template_stats" );
		var dbAdapter = po.getDbAdapter();

		if ( !StructKeyExists( variables, "_recordHitSql" ) ) {
			var tableName        = dbAdapter.escapeEntity( po.getTableName() );
			var hourStart        = dbAdapter.escapeEntity( "hour_start"        );
			var template         = dbAdapter.escapeEntity( "template"          );
			var sendCount        = dbAdapter.escapeEntity( "send_count"        );
			var deliveryCount    = dbAdapter.escapeEntity( "delivery_count"    );
			var openCount        = dbAdapter.escapeEntity( "open_count"        );
			var uniqueOpenCount  = dbAdapter.escapeEntity( "unique_open_count" );
			var clickCount       = dbAdapter.escapeEntity( "click_count"       );
			var failCount        = dbAdapter.escapeEntity( "fail_count"        );
			var spamCount        = dbAdapter.escapeEntity( "spam_count"        );
			var unsubscribeCount = dbAdapter.escapeEntity( "unsubscribe_count" );

			variables._dbadapterName = ListLast( GetMetaData( dbAdapter ).name, "." );

			if ( variables._dbadapterName == "MySqlAdapter" ) {

				variables._recordHitSql =
					"insert into #tableName# (#hourStart#, #template#, #sendCount#, #deliveryCount#, #openCount#, #uniqueOpenCount#, #clickCount#, #failCount#, #spamCount#, #unsubscribeCount#) " &
					"values ( :hour_start, :template, :send_count, :delivery_count, :open_count, :unique_open_count, :click_count, :fail_count, :spam_count, :unsubscribe_count ) " &
					"on duplicate key update {{hit_stat}} = {{hit_stat}} + :{{hit_stat_param}}";

			} else {
				variables._recordHitSql = "";
			}
		}

		if ( !Len( variables._recordHitSql ) ) {
			throw( type="email.log.performance.unsupported.db", message="The #variables._dbadapterName# db adapter is not currently supported by the email log performance extension." );
		}

		var sql = Replace( variables._recordHitSql, "{{hit_stat}}", dbAdapter.escapeEntity( "#arguments.hitStat#_count" ), "all" )
		    sql = Replace( sql, "{{hit_stat_param}}", "#arguments.hitStat#_count", "all" );

		return sql;
	}

	private string function _getRecordClickSql( hitStat ) {
		var po        = $getPresideObject( "email_template_click_stats" );
		var dbAdapter = po.getDbAdapter();

		if ( !StructKeyExists( variables, "_recordClickSql" ) ) {
			var tableName  = dbAdapter.escapeEntity( po.getTableName() );
			var hourStart  = dbAdapter.escapeEntity( "hour_start"      );
			var template   = dbAdapter.escapeEntity( "template"    );
			var link       = dbAdapter.escapeEntity( "link"        );
			var linkBody   = dbAdapter.escapeEntity( "link_body"   );
			var linkTitle  = dbAdapter.escapeEntity( "link_title"  );
			var linkHash   = dbAdapter.escapeEntity( "link_hash"   );
			var clickCount = dbAdapter.escapeEntity( "click_count" );

			variables._dbadapterName = ListLast( GetMetaData( dbAdapter ).name, "." );

			if ( variables._dbadapterName == "MySqlAdapter" ) {

				variables._recordClickSql =
					"insert into #tableName# (#template#, #hourStart#, #link#, #linkBody#, #linkTitle#, #linkHash#, #clickCount# ) " &
					"values ( :template, :hour_start, :link, :link_body, :link_title, :link_hash, :click_count ) " &
					"on duplicate key update #clickCount# = #clickCount# + :click_count";

			} else {
				variables._recordClickSql = "";
			}
		}

		if ( !Len( variables._recordClickSql ) ) {
			throw( type="email.log.performance.unsupported.db", message="The #variables._dbadapterName# db adapter is not currently supported by the email log performance extension." );
		}

		return variables._recordClickSql;
	}

	private function _prepareHitRecordParams( emailTemplateId, hitDate, hitStat, hitCount ) {
		return [
			  { name="hour_start"       , type="cf_sql_integer", value=_getHourStart( arguments.hitDate ) }
			, { name="template"         , type="cf_sql_varchar", value=arguments.emailTemplateId }
			, { name="send_count"       , type="cf_sql_integer", value=arguments.hitStat == "send"        ? arguments.hitCount : 0 }
			, { name="delivery_count"   , type="cf_sql_integer", value=arguments.hitStat == "delivery"    ? arguments.hitCount : 0 }
			, { name="open_count"       , type="cf_sql_integer", value=arguments.hitStat == "open"        ? arguments.hitCount : 0 }
			, { name="unique_open_count", type="cf_sql_integer", value=arguments.hitStat == "unique_open" ? arguments.hitCount : 0 }
			, { name="click_count"      , type="cf_sql_integer", value=arguments.hitStat == "click"       ? arguments.hitCount : 0 }
			, { name="fail_count"       , type="cf_sql_integer", value=arguments.hitStat == "fail"        ? arguments.hitCount : 0 }
			, { name="spam_count"       , type="cf_sql_integer", value=arguments.hitStat == "spam"        ? arguments.hitCount : 0 }
			, { name="unsubscribe_count", type="cf_sql_integer", value=arguments.hitStat == "unsubscribe" ? arguments.hitCount : 0 }
		];
	}

	private function _prepareClickRecordParams( emailTemplateId, hitDate, link, link_body, link_title, clickCount ) {
		var linkHash = Hash( arguments.link & "-" & arguments.link_body & "-" & arguments.link_title );

		return [
			  { name="hour_start" , type="cf_sql_integer", value=_getHourStart( arguments.hitDate ) }
			, { name="template"   , type="cf_sql_varchar", value=arguments.emailTemplateId }
			, { name="link"       , type="cf_sql_varchar", value=arguments.link            }
			, { name="link_body"  , type="cf_sql_varchar", value=arguments.link_body       }
			, { name="link_title" , type="cf_sql_varchar", value=arguments.link_title      }
			, { name="link_hash"  , type="cf_sql_varchar", value=linkHash                  }
			, { name="click_count", type="cf_sql_integer", value=arguments.clickCount      }
		];
	}

	private function _getHourStart( hitDate ) {
		return DateDiff( "h", "1970-01-01 00:00:00", arguments.hitDate );
	}

	private function _migrateTemplateToSummaryTables( templateId ) {
		var startms = GetTickCount();

		$systemOutput( "[EmailLogPerformance] Migrating email template with id [#arguments.templateId#] to summary tables for statistics..." );

		statsSummaryDao.deleteData( filter={ template=arguments.templateId }, skipTrivialInterceptors=true ); // in case of failed previous attempts

		var turnedOnDate = Now();
		var dateFilter   = { filter="email_template_send_log_activity.datecreated <= :datecreated", filterParams={ datecreated=turnedOnDate } };

		templateDao.updateData( id=arguments.templateId, data={
			  stats_collection_enabled    = true
			, stats_collection_enabled_on = turnedOnDate
		} );

		var activityTypes = {
			  send        = "send"
			, deliver     = "delivery"
			, fail        = "fail"
			, open        = "open"
			, click       = "click"
			, markAsSpam  = "spam"
			, unsubscribe = "unsubscribe"
		};

		for( var at in activityTypes ) {
			var summaries = activityDao.selectData(
				  selectFields = [ "count(*) as n", "floor( unix_timestamp( email_template_send_log_activity.datecreated ) / 3600 ) as hour_start" ]
				, filter       = { "message.email_template"=arguments.templateId, activity_type=at }
				, extraFilters = [ dateFilter ]
				, groupBy      = "hour_start"
				, timeout      = 0
			);

			for ( var s in summaries ) {
				recordHit(
					  emailTemplateId = arguments.templateId
					, hitStat         = activityTypes[ at ]
					, hitDate         = DateAdd( "h", s.hour_start, "1970-01-01" )
					, hitCount        = s.n
					, uniqueOpen      = true
				);
			}
		}

		var clicks = activityDao.selectData(
			  selectFields = [ "count(*) as n", "floor( unix_timestamp( email_template_send_log_activity.datecreated ) / 3600 ) as hour_start", "link", "link_body", "link_title" ]
			, filter       = { activity_type="click", "message.email_template"=arguments.templateId }
			, extraFilters = [ dateFilter ]
			, groupBy      = "hour_start,link,link_body,link_title"
			, timeout      = 0
		);

		for( var c in clicks ) {
			_recordClick(
				  emailTemplateId = arguments.templateId
				, hitDate         = DateAdd( "h", c.hour_start, "1970-01-01" )
				, link            = c.link
				, link_body       = c.link_body
				, link_title      = c.link_title
				, clickCount      = c.n
			);
		}

		$systemOutput( "[EmailLogPerformance] Finished migrating email template with id [#arguments.templateId#] in #NumberFormat( GetTickCount()-startms )#ms" );
	}

	private function _getEmailLogPerformanceDateFilters( dateFrom, dateTo ) {
		var extraFilters = [];
		if ( IsDate( arguments.dateFrom ) ) {
			ArrayAppend( extraFilters, {
				  filter = "hour_start >= :dateFrom"
				, filterParams = { dateFrom={ type="cf_sql_integer", value=_epochInHours( arguments.dateFrom ) } }
			});
		}
		if ( IsDate( arguments.dateTo ) ) {
			ArrayAppend( extraFilters, {
				  filter       = "hour_start <= :dateTo"
				, filterParams = { dateTo={ type="cf_sql_integer", value=_epochInHours( arguments.dateTo ) } }
			});
		}

		return extraFilters;
	}
	private function _epochInHours( someDate ) {
		return DateDiff( 'h', '1970-01-01 00:00:00', arguments.someDate );
	}

	private string function _validateStatField( field ) {
		var validFields = [
			  "send_count"
			, "delivery_count"
			, "open_count"
			, "unique_open_count"
			, "click_count"
			, "fail_count"
			, "spam_count"
			, "unsubscribe_count"
		];

		if ( ArrayFind( validFields, arguments.field ) ) {
			return arguments.field;
		}

		throw( type="email.logging.invalid.stat.field", message="The statistics field, [#arguments.field#], is not a valid field to get a hit count for." );
	}
}