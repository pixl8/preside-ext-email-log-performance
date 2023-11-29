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
	property name="template" relationship="many-to-one" relatedto="email_template"           uniqueindexes="clickstatlink|1";
	property name="hour_start" type="numeric" dbtype="int" required=true indexes="hourstart" uniqueindexes="clickstatlink|2";
	property name="link_hash"  type="string"  dbtype="varchar" maxlength=32 required=true    uniqueindexes="clickstatlink|3" indexes="linkhash";
	property name="link"       type="string"  dbtype="varchar" maxlength=750  indexes="link";
	property name="link_title" type="string"  dbtype="text";
	property name="link_body"  type="string"  dbtype="text";

	property name="click_count" type="numeric" dbtype="int" required=true default=0;
}