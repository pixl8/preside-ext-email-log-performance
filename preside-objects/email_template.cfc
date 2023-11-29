/**
 * Decorate core email template object with flags
 * to turn on our enhanced stats collection per template.
 * This allows for a smooth data migration.
 *
 */
component {
	property name="stats_collection_enabled"    type="boolean" dbtype="boolean" default=true indexes="statscollectionenabled";
	property name="stats_collection_enabled_on" type="numeric" dbtype="int"                  indexes="statscollectionenabledon";
}