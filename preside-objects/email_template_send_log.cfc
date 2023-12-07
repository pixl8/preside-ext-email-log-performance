/**
 * Decorate email send log to add open counter increments
 * directly on the object
 *
 */
component {
	property name="open_count" type="numeric" dbtype="int" default=0 indexes="open_count";
}