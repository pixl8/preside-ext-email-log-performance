component {

	property name="emailLogPerformanceService" inject="emailLogPerformanceService";

	private void function runAsync() {
		emailLogPerformanceService.migrateToSummaryTables();
	}
}