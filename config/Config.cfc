component {

	variables._extMapping = "app.extensions.preside-ext-email-log-performance";

	public void function configure( required struct config ) {
		var conf     = arguments.config;
		var settings = conf.settings ?: {};

		_setupInterceptors( conf );
	}

// helpers
	private void function _setupInterceptors( conf ) {
		ArrayAppend( conf.interceptors, { class="#_extMapping#.interceptors.EmailLogPerformanceInterceptors", properties={} } );
	}
}
