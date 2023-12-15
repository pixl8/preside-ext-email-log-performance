/**
 * @versioned      false
 * @useCache       false
 * @noid           true
 * @nodatemodified true
 * @nodatecreated  true
 * @nolabel        true
 * @tablePrefix    psys_
 *
 */
component {
	property name="template" relationship="many-to-one" relatedto="email_template"                     uniqueindexes="hourstartemplate|1";
	property name="hour_start" type="numeric" dbtype="int" required=true           indexes="hourstart" uniqueindexes="hourstartemplate|2";

	property name="send_count"        type="numeric" dbtype="int" required=true default=0;
	property name="delivery_count"    type="numeric" dbtype="int" required=true default=0;
	property name="open_count"        type="numeric" dbtype="int" required=true default=0;
	property name="unique_open_count" type="numeric" dbtype="int" required=true default=0;
	property name="click_count"       type="numeric" dbtype="int" required=true default=0;
	property name="fail_count"        type="numeric" dbtype="int" required=true default=0;
	property name="spam_count"        type="numeric" dbtype="int" required=true default=0;
	property name="unsubscribe_count" type="numeric" dbtype="int" required=true default=0;
}