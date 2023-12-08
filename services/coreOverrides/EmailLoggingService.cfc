/**
 * This is not best practice for an extension
 * to override a core service but little option
 * here. Also this is an experimental and
 * hopefully temporary extension.
 *
 */
component extends="preside.system.services.email.EmailLoggingService" {

	property name="sqlRunner"                  inject="sqlRunner";
	property name="emailLogPerformanceService" inject="emailLogPerformanceService";
	property name="presideObjectService"       inject="presideObjectService";

	/**
	 * Overriding mark as opened to fix unique open issue
	 *
	 */
	public void function markAsOpened( required string id, boolean softMark=false ) {
		var data = { opened = true, opened_count=1 };

		if ( !arguments.softMark ) {
			data.opened_date = _getNow();
		}

		var updated = $getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( opened is null or opened = :opened )"
			, filterParams = { id=arguments.id, opened=false }
			, data         = data
		);

		markAsDelivered( arguments.id, true );
		recordActivity( messageId=arguments.id, activity="open", uniqueOpen=( updated > 0 ) );
	}

	/**
	 * Overriding click recording for efficiency
	 *
	 */
	public void function recordClick( required string id, required string link, string linkTitle="", string linkBody="" ) {
		var dao     = $getPresideObject( "email_template_send_log" );
		var updated = sqlRunner.runSql(
			  dsn        = dao.getDsn()
			, sql        = _getRecordClickSql()
			, params     = _getRecordClickParams( arguments.id )
			, returnType = "info"
		);

		$SystemOutput( "Send log result: #SerializeJson( updated )#" );


		if ( Val( updated.recordCount ?: 0 ) > 0 ) {
			recordActivity(
				  messageId = arguments.id
				, activity  = "click"
				, extraData = { link=arguments.link, link_title=arguments.linkTitle, link_body=arguments.linkBody }
			);
		}

		markAsOpened( id=id, softMark=true );
	}

	/**
	 * Orverriding markAsDelivered to ensure we always record the activity,
	 * even when softmarking
	 *
	 */
	public void function markAsDelivered( required string id, boolean softMark=false ) {
		var data = {
			  delivered         = true
			, hard_bounced      = false
			, hard_bounced_date = ""
			, failed            = false
			, failed_date       = ""
			, failed_reason     = ""
			, failed_code       = ""
		};

		if ( !arguments.softMark ) {
			data.delivered_date = _getNow();
		}

		var updated = $getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( delivered is null or delivered = :delivered )"
			, filterParams = { id=arguments.id, delivered=false }
			, data         = data
		);

		if ( updated ) {
			recordActivity(
				  messageId = arguments.id
				, activity  = "deliver"
			);
		}

	}

	/**
	 * Overriding to increment our stats
	 * tables
	 *
	 */
	public void function recordActivity(
		  required string  messageId
		, required string  activity
		,          struct  extraData = {}
		,          string  userIp    = cgi.remote_addr
		,          string  userAgent = cgi.http_user_agent
		,          boolean uniqueOpen
	) {
		var fieldsToAddFromExtraData = [ "link", "code", "reason", "link_title", "link_body" ];
		var extra = StructCopy( arguments.extraData );
		var data = {
			  message       = arguments.messageId
			, activity_type = arguments.activity
			, user_ip       = arguments.userIp
			, user_agent    = arguments.userAgent
		};

		for( var field in extra ) {
			if ( ArrayFind( fieldsToAddFromExtraData, LCase( field ) ) ) {
				data[ field ] = extra[ field ];
				extra.delete( field );
			}
		}
		data.extra_data = SerializeJson( extra );

		try {
			$announceInterception( "onEmail#arguments.activity#", data );
		} catch( any e ) {
			$raiseError( e );
		}

		try {
			$getPresideObject( "email_template_send_log_activity" ).insertData( data );
			_processEventForStatsTables(
				  message    = data.message
				, activity   = arguments.activity
				, data       = data
				, uniqueOpen = arguments.uniqueOpen
			);
		} catch( database e ) {
			// ignore missing logs when recording activity - but record the error for
			// info only
			$raiseError( e );
		}
	}

// private helpers
	private function _getRecordClickSql() {
		if ( !StructKeyExists( variables, "_recordClickSql" ) ) {
			var dao = $getPresideObject( "email_template_send_log" );
			var adapter = dao.getDbAdapter();
			var tableName = adapter.escapeEntity( dao.getTableName() );
			var countCol  = adapter.escapeEntity( "click_count" );
			var idCol = adapter.escapeEntity( "id" );

			variables._recordClickSql = "update #tableName# set #countCol# = #countCol# + 1 where #idCol# = :id";
		}

		return variables._recordClickSql;
	}

	private function _getRecordClickParams( sendLogId ) {
		return [{
			  type = "cf_sql_varchar"
			, value = arguments.sendLogId
			, name = "id"
		}];
	}

	private function _processEventForStatsTables( message, activity, data={}, uniqueOpen ) {
		if ( !Len( arguments.message ) ) {
			return;
		}

		var template = presideObjectService.selectData(
			  objectName   = "email_template_send_log"
			, selectFields = [ "email_template" ]
			, forceJoins   = "inner"
			, filter       = {
				  id                                        = arguments.message
				, "email_template.stats_collection_enabled" = true
			  }
		);

		if ( Len( template.email_template ) ) {
			emailLogPerformanceService.recordHit(
				  emailTemplateId = template.email_template
				, hitDate         = Now()
				, hitStat         = _activityToHitStat( arguments.activity )
				, uniqueOpen      = arguments.uniqueOpen
				, data            = arguments.data
			);
		}
	}

	private function _activityToHitStat( activity ) {
		switch( arguments.activity ) {
			case "deliver": return "delivery";
			case "markasspam": return "spam";
		}

		return arguments.activity;
	}

	private array function _getLib() {
		if ( !_lib.len() ) {
			var libDir = ExpandPath( "/preside/system/services/email/lib" );
			_lib = DirectoryList( libDir, false, "path", "*.jar" );
		}
		return _lib;
	}
}