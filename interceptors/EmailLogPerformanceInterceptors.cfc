component extends="coldbox.system.Interceptor" {

	property name="emailLogPerformanceService" inject="delayedInjector:emailLogPerformanceService";
	property name="presideObjectService"       inject="delayedInjector:presideObjectService";

// PUBLIC
	public void function configure() {}

	public void function onEmailSend( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="send" );
	}
	public void function onEmailDeliver( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="delivery" );
	};
	public void function onEmailOpen( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="open" );
	};
	public void function onEmailClick( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="click", data=arguments.interceptData );
	};

	public void function onEmailFail( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="fail" );
	};
	public void function onEmailMarkasspam( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="spam" );
	};
	public void function onEmailUnsubscribe( event, interceptData ) {
		_processEvent( message=arguments.interceptData.message ?: "", action="unsubscribe" );
	};


// PRIVATE HELPERS
	private function _processEvent( message, action, data={} ) {
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
				, hitStat         = arguments.action
			);

			if ( arguments.action == "click" ) {
				emailLogPerformanceService.recordClick(
					  argumentCollection = arguments.data
					, emailTemplateId    = template.email_template
					, hitDate            = Now()
				);
			}
		}
	}
}