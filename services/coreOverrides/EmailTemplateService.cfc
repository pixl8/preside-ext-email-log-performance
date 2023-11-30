/**
 * This is not best practice for an extension
 * to override a core service but little option
 * here. Also this is an experimental and
 * hopefully temporary extension.
 *
 */
component extends="preside.system.services.email.EmailTemplateService" {

	property name="emailLogPerformanceService" inject="emailLogPerformanceService";

	/**
	 * Additional method to return whether or not the given template
	 * is configured to use the performant logging technique
	 *
	 */
	public boolean function usePerformantLogging( required string templateId ) {
		var requestCacheKey = "_usePerformantLogging#arguments.templateId#";

		if ( !StructKeyExists( request, requestCacheKey ) ) {
			request[ requestCacheKey ] = $getPresideObject( "email_template" ).dataExists( filter={
				  id                       = arguments.templateId
				, stats_collection_enabled = true
			} );
		}

		return request[ requestCacheKey ];
	}

	/**
	 * Override stat fetching methods to use our summary tables
	 *
	 */
	public numeric function getSentCount( required string templateId, string dateFrom="", string dateTo="" ) {
		return _getEmailLogPerformanceCount( argumentCollection=arguments, field="send_count", method="getSentCount" );
	}

	public numeric function getOpenedCount( required string templateId, string dateFrom="", string dateTo="" ) {
		return _getEmailLogPerformanceCount( argumentCollection=arguments, field="open_count", method="getOpenedCount" );
	}

	public numeric function getDeliveredCount( required string templateId, string dateFrom="", string dateTo="" ) {
		return _getEmailLogPerformanceCount( argumentCollection=arguments, field="delivery_count", method="getDeliveredCount" );
	}

	public numeric function getClickCount( required string templateId, string dateFrom="", string dateTo="" ) {
		return _getEmailLogPerformanceCount( argumentCollection=arguments, field="click_count", method="getClickCount" );
	}

	public numeric function getFailedCount( required string templateId, string dateFrom="", string dateTo="" ) {
		return _getEmailLogPerformanceCount( argumentCollection=arguments, field="fail_count", method="getFailedCount" );
	}

	public struct function getStats(
		  required string  templateId
		,          string  dateFrom   = getFirstStatDate( arguments.templateId )
		,          string  dateTo     = getLastStatDate( arguments.templateId )
		,          numeric timePoints = 1
		,          boolean uniqueOpens = ( arguments.timePoints == 1 )
	) {
		if ( arguments.timePoints == 1 || !usePerformantLogging( arguments.templateId ) ) {
			return super.getStats( argumentCollection=arguments );
		}

		return emailLogPerformanceService.getStats( argumentCollection=arguments );
	}

	public struct function getLinkClickStats(
		  required string templateId
		,          string dateFrom = ""
		,          string dateTo   = ""
	) {
		if ( !usePerformantLogging( arguments.templateId ) ) {
			return super.getLinkClickStats( argumentCollection=arguments );
		}

		return emailLogPerformanceService.getLinkClickStats( argumentCollection=arguments );
	}

	public any function getFirstStatDate( required string templateId ) {
		if ( !usePerformantLogging( arguments.templateId ) ) {
			return super.getFirstStatDate( argumentCollection=arguments );
		}
		return emailLogPerformanceService.getFirstStatDate( arguments.templateId );
	}

	public any function getLastStatDate( required string templateId ) {
		if ( !usePerformantLogging( arguments.templateId ) ) {
			return super.getFirstStatDate( argumentCollection=arguments );
		}
		return emailLogPerformanceService.getLastStatDate( arguments.templateId );
	}

// helpers
	private function _getEmailLogPerformanceCount( templateId, dateFrom, dateTo, field, method ) {
		if ( !usePerformantLogging( arguments.templateId ) ) {
			return super[ arguments.method ]( argumentCollection=arguments );
		}

		return emailLogPerformanceService.getStatCount(
			  templateId = arguments.templateId
			, field      = arguments.field
			, dateFrom   = arguments.dateFrom
			, dateTo     = arguments.dateTo
		);
	}

}