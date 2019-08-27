----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Florian Seliger, ETH Zurich, July 2019, seliger@kof.ethz.ch
-- In this code, we build a bridge file in order to assign any patent number to its "first patent filing" (that can be identified in PATSTAT).
-- We run this code on PATSTAT Spring 2019.
-- For details, see de Rassenfosse, Kozak, Seliger 2019: Geocoding of worldwide patent data, available at https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3425764 Section "Usage Notes".
-- We first insert all Paris Convention priority and subsequent filings, then all filings referring to PCT applications, continuals and technical relationships.
-- Finally, we insert singletons (there are no subsequent filings for singletons). 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------


DROP TABLE IF EXISTS first_and_subsequent_filings;
CREATE TABLE first_and_subsequent_filings AS
SELECT DISTINCT t1.prior_appln_id, t2.*, t3.appln_auth, t3.appln_kind, t3.appln_filing_date, t3.appln_filing_year, t3.earliest_publn_date, t3.earliest_publn_year, t3.earliest_pat_publn_id, t3.granted, t3.docdb_family_id, t3.inpadoc_family_id  FROM
tls204_appln_prior t1 
JOIN tls211_pat_publn t2 
ON t1.appln_id = t2.appln_id
JOIN tls201_appln t3
ON t1.appln_id = t3.appln_id
UNION
SELECT DISTINCT t1.prior_appln_id, t2.*, t3.appln_auth, t3.appln_kind, t3.appln_filing_date, t3.appln_filing_year, t3.earliest_publn_date, t3.earliest_publn_year, t3.earliest_pat_publn_id, t3.granted, t3.docdb_family_id, t3.inpadoc_family_id  FROM
tls204_appln_prior t1
JOIN tls211_pat_publn t2
ON t1.prior_appln_id = t2.appln_id
JOIN tls201_appln t3
ON t1.prior_appln_id = t3.appln_id
;

ALTER TABLE first_and_subsequent_filings ADD COLUMN TYPE TEXT;
UPDATE first_and_subsequent_filings set TYPE = 'PRIORITY';

INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.appln_id, t2.*, t1.appln_auth, t1.appln_kind, t1.appln_filing_date, t1.appln_filing_year, t1.earliest_publn_date, t1.earliest_publn_year, t1.earliest_pat_publn_id, t1.granted, t1.docdb_family_id, t1.inpadoc_family_id, 'PCT'  
 FROM tls201_appln t1
JOIN tls211_pat_publn t2 
ON t1.appln_id = t2.appln_id
LEFT OUTER JOIN first_and_subsequent_filings t3 on t1.appln_id = t3.appln_id
WHERE internat_appln_id = 0 and t1.appln_kind = 'W' and t3.appln_id is null and t1.appln_id = t1.earliest_filing_id;

INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.internat_appln_id, t2.*, t1.appln_auth, t1.appln_kind, t1.appln_filing_date, t1.appln_filing_year, t1.earliest_publn_date, t1.earliest_publn_year, t1.earliest_pat_publn_id, t1.granted, t1.docdb_family_id, t1.inpadoc_family_id, 'PCT'  
 FROM tls201_appln t1
JOIN tls211_pat_publn t2 
ON t1.appln_id = t2.appln_id
JOIN first_and_subsequent_filings t3 on t1.internat_appln_id = t3.prior_appln_id
WHERE internat_appln_id != 0 and (t1.reg_phase = 'Y' or t1.nat_phase = 'Y')  
and t3.TYPE = 'PCT';


INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.parent_appln_id, t2.*, t3.appln_auth, t3.appln_kind, t3.appln_filing_date, t3.appln_filing_year, t3.earliest_publn_date, t3.earliest_publn_year, t3.earliest_pat_publn_id, t3.granted, t3.docdb_family_id, t3.inpadoc_family_id, 'CONTINUAL'  
 FROM TLS216_APPLN_CONTN t1
JOIN tls211_pat_publn t2 
ON t1.parent_appln_id = t2.appln_id
JOIN tls201_appln t3
ON t1.parent_appln_id = t3.appln_id
LEFT OUTER JOIN first_and_subsequent_filings t4 on t1.parent_appln_id = t4.appln_id
WHERE t4.appln_id is null;

INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.parent_appln_id, t2.*, t3.appln_auth, t3.appln_kind, t3.appln_filing_date, t3.appln_filing_year, t3.earliest_publn_date, t3.earliest_publn_year, t3.earliest_pat_publn_id, t3.granted, t3.docdb_family_id, t3.inpadoc_family_id, 'CONTINUAL'  
 FROM TLS216_APPLN_CONTN t1
JOIN tls211_pat_publn t2 
ON t1.appln_id = t2.appln_id
JOIN tls201_appln t3
ON t1.appln_id = t3.appln_id
JOIN first_and_subsequent_filings t4 on t1.parent_appln_id = t4.prior_appln_id;

INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.tech_rel_appln_id, t2.*, t3.appln_auth, t3.appln_kind, t3.appln_filing_date, t3.appln_filing_year, t3.earliest_publn_date, t3.earliest_publn_year, t3.earliest_pat_publn_id, t3.granted, t3.docdb_family_id, t3.inpadoc_family_id, 'TECH_REL'  
 FROM TLS205_TECH_REL t1
JOIN tls211_pat_publn t2 
ON t1.tech_rel_appln_id = t2.appln_id
JOIN tls201_appln t3
ON t1.tech_rel_appln_id = t3.appln_id
LEFT OUTER JOIN first_and_subsequent_filings t4 on t1.tech_rel_appln_id = t4.appln_id
WHERE t4.appln_id is null;

INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.tech_rel_appln_id, t2.*, t3.appln_auth, t3.appln_kind, t3.appln_filing_date, t3.appln_filing_year, t3.earliest_publn_date, t3.earliest_publn_year, t3.earliest_pat_publn_id, t3.granted, t3.docdb_family_id, t3.inpadoc_family_id, 'TECH_REL'  
FROM TLS205_TECH_REL t1
JOIN tls211_pat_publn t2 
ON t1.appln_id = t2.appln_id
JOIN tls201_appln t3
ON t1.appln_id = t3.appln_id
JOIN first_and_subsequent_filings t4 on t1.tech_rel_appln_id = t4.prior_appln_id;


-- Singletons

INSERT INTO first_and_subsequent_filings
SELECT DISTINCT t1.appln_id, t2.*, t1.appln_auth, t1.appln_kind, t1.appln_filing_date, t1.appln_filing_year, t1.earliest_publn_date, t1.earliest_publn_year, t1.earliest_pat_publn_id, t1.granted, t1.docdb_family_id, t1.inpadoc_family_id, 'SINGLE' 
  FROM tls201_appln t1
JOIN tls211_pat_publn t2 
ON t1.appln_id = t2.appln_id
JOIN (select docdb_family_id
from tls201_appln
group by docdb_family_id
having count(distinct appln_id) = 1) as t3
on t1.docdb_family_id = t3.docdb_family_id
LEFT OUTER JOIN first_and_subsequent_filings t4 on t1.appln_id = t4.appln_id
WHERE t4.appln_id is null
;


CREATE INDEX first_and_subsequent_filings_prior_appln_id on first_and_subsequent_filings(prior_appln_id);
CREATE INDEX first_and_subsequent_filings_appln_id on first_and_subsequent_filings(appln_id);
