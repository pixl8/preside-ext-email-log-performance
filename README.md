# Email Log Performance

A proof-of-concept extension to help with statistics performance for application sending a lot of email. The idea is that this logic will eventually make its way into Preside core (see [PRESIDECMS-2749](https://presidecms.atlassian.net/browse/PRESIDECMS-2749)).

DO NOT USE! (OR AT YOUR OWN RISK)

## How it works

The extension adds a pair of [summary tables](https://mysql.rjweb.org/doc.php/summarytables) to collect count summaries for email clicks, opens, etc. in time buckets of one hour.

It then replaces all statistic querying logic in Preside to use these tables.

The extension includes a db data migration to populate these tables from existing data. If your application has a lot of data, expect/account for this to take a VERY long time.