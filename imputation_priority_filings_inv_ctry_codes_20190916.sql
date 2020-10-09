/***************************************************************************************************************************
 
  Algorithm to impute missing country codes of priority filings by inventors from subsequent filings
   
  This code builds on the work of: G. de Rassenfosse (EPFL Switzerland)
  It was written by Florian Seliger in February 2020 using PostgreSQL and Patstat Spring 2019.
 
  Please acknowledge the work and cite the companion paper:
  de Rassenfosse, G., Dernis, H., Guellec, D., Picci, L., van Pottelsberghe de la Potterie, B., 2013. 
  The worldwide count of priority patents: A new indicator of inventive activity. Research Policy
 
  Florian Seliger would like to thank Charles Clavadetscher (KOF ETHZ) and Matthias Bannert (KOF ETHZ) for their help.
 
  Description : PostgreSQL code for PATSTAT to impute missing country information (country) for priority filings based on the inventor criterion. 
  When the information on inventors' country codes is missing, the algorithm looks into direct equivalents and other subsequent filings for the information. 
  Information can also be retrieved from applicants' country code.
 
  NOTE: 
  - In contrast to prior versions of this code, we do not apply any filters on publication kind codes and years. The only filter is on patent offices (see below).
    Patstat may not be complete for early and recent years and the resulting data need to be checked critically against this! 
  - We also include filings where the publication information is missing in Patstat for whatever reasons.
  - You can re-activate all filters if needed. The code is simply commented out.  
  - In contrast to prior versions, we include the person_id from Patstat in the output file. The person_id may be useful for some purposes, but it does not allow to trace inventors over time.
 
 
  Output: table PF_INV_PERS_CTRY_ALL. The field 'source' indicates where the information on
  inventors come from :  1 = information available from the patent itself
                         2 = information availabe from the earliest direct equivalent
                         3 = information available from the earliest subsequent filing
                            4 = applicants' information from the patent itself 
                            5 = applicants' information from earliest direct equivalent
                            6 = applicants' information from earliest subsequent filing
                         
  The following 52 patent offices are browsed (EU27 + OECD + BRICS + EPO + WIPO): 
  AL,AT,AU,BE,BG,BR,CA,CH,CL,CN,CY,CZ,DE,DK,EE,EP,ES,FI,FR,GB,GR,HR, HU,IB,IE,IL,IN,IS,IT,JP,KR,LT,LU,LV,MK,MT,MX,NL,NO,NZ,PL,PT,RO,RS,RU,SE,SI,SK,SM,TR,US,ZA.
 
******************************************************************************************/
 
/*
  CREATE ALL TABLES NEEDED
*/
 
 
-- table containing the patent offices to browse
DROP TABLE IF EXISTS po;
CREATE TABLE po (
patent_office CHAR(2) DEFAULT NULL
) ; COMMENT ON TABLE po IS 'List of patent offices to browse';
INSERT INTO po VALUES ('AL'), ('AT'), ('AU'), ('BE'), ('BG'),('BR'), ('CA'), ('CH'), ('CL'), ('CN'),('CY'), ('CZ'), ('DE'), ('DK'), ('EE'), ('EP'), ('ES'), ('FI'), ('FR'), ('GB'), ('GR'), ('HR'), ('HU'),('IB'), ('IE'), ('IL'), ('IN'), ('IS'), ('IT'), ('JP'), ('KR'), ('LT'), ('LU'), ('LV'), ('MK'), ('MT'), ('MX'), ('NL'), ('NO'), ('NZ'), ('PL'), ('PT'), ('RO'), ('RS'), ('RU'), ('SE'), ('SI'), ('SK'), ('SM'), ('TR'), ('US'), ('ZA');
DROP INDEX IF EXISTS po_idx;
CREATE INDEX po_idx ON po USING btree (patent_office);
 
-- table containing the appln_id to exclude from the analysis (e.g. petty patents) for a given patent office
/* 
DROP TABLE IF EXISTS toExclude;
CREATE TABLE toExclude AS
SELECT DISTINCT appln_id, publn_auth, publn_kind FROM patstat.patstat.tls211_pat_publn
WHERE 
(publn_auth='AU' AND (publn_kind='A3' OR publn_kind='B3' OR publn_kind='B4' OR publn_kind='C1'
OR publn_kind='C4' OR publn_kind='D0'))
OR 
(publn_auth='BE' AND (publn_kind='A6' OR publn_kind='A7'))
OR 
(publn_auth='FR' AND (publn_kind='A3' OR publn_kind='A4' OR publn_kind='A7'))
OR
(publn_auth='IE' AND (publn_kind='A2' OR publn_kind='B2'))
OR
(publn_auth='NL' AND publn_kind='C1')
OR 
(publn_auth='SI' AND publn_kind='A2')
OR
(publn_auth='US' AND (publn_kind='E' OR publn_kind='E1' OR publn_kind='H' OR publn_kind='H1' OR publn_kind='I4' 
OR publn_kind='P' OR publn_kind='P1' OR publn_kind='P2' OR publn_kind='P3' OR publn_kind='S1'))
;   COMMENT ON TABLE toExclude IS 'Excluded appln_id for a given po based on publn_kind';
 
DROP INDEX IF EXISTS exclude_idx;
CREATE INDEX exclude_idx ON toExclude USING btree (appln_id);
*/ 
-- Table containing the priority filings of a given (patent office, year)

DROP TABLE IF EXISTS PRIORITY_FILINGS_inv;
CREATE TABLE PRIORITY_FILINGS_inv (
appln_id INT,
appln_kind CHAR,
person_id INT,
patent_office VARCHAR(2),
appln_filing_year INT,
appln_filing_date DATE,
type TEXT
  );


INSERT INTO PRIORITY_FILINGS_inv
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'priority'
FROM patstat.tls201_appln t1 
JOIN patstat.tls204_appln_prior t2 ON t1.appln_id = t2.prior_appln_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
WHERE (t1.appln_kind != 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'priority'
FROM patstat.tls201_appln t1 
JOIN patstat.tls204_appln_prior t2 ON t1.appln_id = t2.prior_appln_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
--JOIN po t5 ON t1.appln_auth = t5.patent_office
  --newer Patstat versions:
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
;


 
INSERT INTO PRIORITY_FILINGS_inv
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth AS patent_office, t1.appln_filing_year, t1.appln_filing_date, 'pct'
FROM patstat.tls201_appln t1 
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
--JOIN po t5 ON t1.appln_auth = t5.patent_office
  --newer Patstat versions:
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id

  LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0 and nat_phase = 'N' and reg_phase = 'N'
AND t1.appln_id = t1.earliest_filing_id
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;


INSERT INTO PRIORITY_FILINGS_inv
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'continual'
FROM patstat.tls201_appln t1 
JOIN patstat.tls216_appln_contn t2 ON t1.appln_id = t2.parent_appln_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id

    LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind != 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'continual'
FROM patstat.tls201_appln t1 
JOIN patstat.tls216_appln_contn t2 ON t1.appln_id = t2.parent_appln_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
--JOIN po t5 ON t1.appln_auth = t5.patent_office
--newer Patstat versions:
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'tech_rel'
FROM patstat.tls201_appln t1 
JOIN patstat.tls205_tech_rel t2 ON t1.appln_id = t2.tech_rel_appln_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind != 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'tech_rel'
FROM patstat.tls201_appln t1 
JOIN patstat.tls205_tech_rel t2 ON t1.appln_id = t2.tech_rel_appln_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
--JOIN po t5 ON t1.appln_auth = t5.patent_office
--newer Patstat versions:
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

-- Singletons
INSERT INTO PRIORITY_FILINGS_inv
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'single'
FROM patstat.tls201_appln t1 
JOIN (SELECT docdb_family_id from patstat.tls201_appln group by docdb_family_id having count(distinct appln_id) = 1) as t2
ON t1.docdb_family_id = t2.docdb_family_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
  JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind != 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'single'
FROM patstat.tls201_appln t1 
JOIN (SELECT docdb_family_id from patstat.tls201_appln group by docdb_family_id having count(distinct appln_id) = 1) as t2
ON t1.docdb_family_id = t2.docdb_family_id
--LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
--JOIN po t5 ON t1.appln_auth = t5.patent_office
--newer Patstat versions:
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
--AND t3.appln_id IS NULL
--AND t4.publn_nr IS NOT NULL 
--AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
--AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

DROP INDEX IF EXISTS pfa_idx, pfa_idx2, pfa_idx3;
CREATE INDEX pfa_idx ON PRIORITY_FILINGS_inv USING btree (appln_id);
CREATE INDEX pfa_idx2 ON PRIORITY_FILINGS_inv USING btree (patent_office);
CREATE INDEX pfa_idx3 ON PRIORITY_FILINGS_inv USING btree (appln_filing_year);
 
 
 
-- Table containing appln_id, person_id, ctry_code
 
-- Table containing appln_id, person_id, ctry_code
DROP TABLE IF EXISTS country_codes_inv;
CREATE TABLE country_codes_inv AS
SELECT DISTINCT t1.appln_id, t1.person_id, t2.person_ctry_code AS ctry_code 
FROM patstat.tls207_pers_appln t1
JOIN patstat.tls206_person t2 ON t1.person_id = t2.person_id
WHERE invt_seq_nr > 0;

DROP TABLE IF EXISTS country_codes_app;
CREATE TABLE country_codes_app AS
SELECT DISTINCT t1.appln_id, t1.person_id, t2.person_ctry_code AS ctry_code 
FROM patstat.tls207_pers_appln t1
JOIN patstat.tls206_person t2 ON t1.person_id = t2.person_id
WHERE applt_seq_nr > 0;

DROP INDEX IF EXISTS country_codes_inv_idx, country_codes_app_idx, country_codes_pers_inv_idx, country_codes_pers_app_idx;
CREATE INDEX country_codes_inv_idx ON country_codes_inv USING btree (appln_id);
CREATE INDEX country_codes_app_idx ON country_codes_app USING btree (appln_id);                  
CREATE INDEX country_codes_pers_inv_idx ON country_codes_inv USING btree (person_id);
CREATE INDEX country_codes_pers_app_idx ON country_codes_app USING btree (person_id);  

 
/* 
Create the tables that will be used to impute missing information
*/
 
-- Inventor information
 
-- A. Information that is directly available (source = 1)
DROP TABLE IF EXISTS PRIORITY_FILINGS1;
CREATE TABLE PRIORITY_FILINGS1 AS (
-- first of all we need all priority filings with address information in Patstat and country information
SELECT DISTINCT t1.appln_id, t1.person_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, ctry_code, type
FROM PRIORITY_FILINGS_inv t1 
LEFT OUTER JOIN country_codes_inv t2 ON t1.appln_id = t2.appln_id AND t1.person_id = t2.person_id) ;
DROP INDEX IF EXISTS pri1_idx, pri1_pers_idx, pri1_office_idx, pri1_year;
CREATE INDEX pri1_idx ON PRIORITY_FILINGS1 USING btree (appln_id);
CREATE INDEX pri1_pers_idx ON PRIORITY_FILINGS1 USING btree (person_id);
CREATE INDEX pri1_office_idx ON PRIORITY_FILINGS1 USING btree (patent_office);
CREATE INDEX pri1_year_idx ON PRIORITY_FILINGS1 USING btree (appln_filing_year);
 
-- B. Prepare a pool of all potential second filings
CREATE TABLE t AS
SELECT t1.appln_id, t3.appln_id AS subsequent_id, t3.appln_filing_date AS subsequent_date, max(t4.prior_appln_seq_nr) AS nb_priorities
FROM PRIORITY_FILINGS_inv t1 
INNER JOIN patstat.tls204_appln_prior t2 ON t2.prior_appln_id = t1.appln_id
INNER JOIN patstat.tls201_appln t3 ON t3.appln_id = t2.appln_id
INNER JOIN patstat.tls204_appln_prior t4 ON t4.appln_id = t3.appln_id
WHERE type = 'priority'
GROUP BY t1.appln_id, t3.appln_id, t3.appln_filing_date ;
CREATE INDEX t_appln_id ON t(appln_id);  

DROP TABLE IF EXISTS SUBSEQUENT_FILINGS1;
CREATE TABLE SUBSEQUENT_FILINGS1 AS (
SELECT DISTINCT t1.appln_id, t.subsequent_id, t2.person_id as subsequent_person_id, applt_seq_nr, invt_seq_nr, t1.patent_office, t1.appln_filing_year, t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
JOIN patstat.tls207_pers_appln t2 ON (t.subsequent_id = t2.appln_id)
ORDER BY t1.appln_id, t.subsequent_date, t2.person_id, applt_seq_nr, invt_seq_nr ASC);



DROP TABLE t;
CREATE TABLE t AS
SELECT t1.appln_id, t3.appln_id AS subsequent_id, t3.appln_filing_date AS subsequent_date, max(count) AS nb_priorities
FROM PRIORITY_FILINGS_inv t1 
INNER JOIN patstat.tls216_appln_contn t2 ON t2.parent_appln_id = t1.appln_id
INNER JOIN patstat.tls201_appln t3 ON t3.appln_id = t2.appln_id
INNER JOIN (select appln_id, count(*) from patstat.tls216_appln_contn group by appln_id) as t4 ON t4.appln_id = t3.appln_id
WHERE type = 'continual'
GROUP BY t1.appln_id, t3.appln_id, t3.appln_filing_date ;
CREATE INDEX t_appln_id ON t(appln_id);      

INSERT INTO SUBSEQUENT_FILINGS1
SELECT DISTINCT t1.appln_id, t.subsequent_id, t2.person_id as subsequent_person_id, applt_seq_nr, invt_seq_nr, t1.patent_office, t1.appln_filing_year, t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
JOIN patstat.tls207_pers_appln t2 ON (t.subsequent_id = t2.appln_id)
ORDER BY t1.appln_id, t.subsequent_date, t2.person_id, applt_seq_nr, invt_seq_nr ASC;

DROP TABLE t;
CREATE TABLE t AS
SELECT t1.appln_id, t3.appln_id AS subsequent_id, t3.appln_filing_date AS subsequent_date, max(count) AS nb_priorities
FROM PRIORITY_FILINGS_inv t1 
INNER JOIN patstat.TLS205_TECH_REL t2 ON t2.tech_rel_appln_id = t1.appln_id
INNER JOIN patstat.tls201_appln t3 ON t3.appln_id = t2.appln_id
INNER JOIN (select appln_id, count(*) from patstat.TLS205_TECH_REL group by appln_id) as t4 ON t4.appln_id = t3.appln_id
WHERE type = 'tech_rel'
GROUP BY t1.appln_id, t3.appln_id, t3.appln_filing_date ;
CREATE INDEX t_appln_id ON t(appln_id);  

INSERT INTO SUBSEQUENT_FILINGS1 
SELECT DISTINCT t1.appln_id, t.subsequent_id, t2.person_id as subsequent_person_id, applt_seq_nr, invt_seq_nr, t1.patent_office, t1.appln_filing_year, t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
JOIN patstat.tls207_pers_appln t2 ON (t.subsequent_id = t2.appln_id)
ORDER BY t1.appln_id, t.subsequent_date, t2.person_id, applt_seq_nr, invt_seq_nr ASC;

DROP TABLE t;
CREATE TABLE t AS
SELECT t1.appln_id, t2.appln_id AS subsequent_id, t2.appln_filing_date AS subsequent_date
FROM PRIORITY_FILINGS_inv t1 
INNER JOIN patstat.tls201_appln t2 ON t1.appln_id = t2.internat_appln_id
WHERE type = 'pct'
AND t2.internat_appln_id != 0 and reg_phase = 'Y'
GROUP BY t1.appln_id, t2.appln_id, t2.appln_filing_date ;
CREATE INDEX t_appln_id ON t(appln_id);      

INSERT INTO subsequent_filings1
SELECT DISTINCT t1.appln_id, t.subsequent_id, t2.person_id as subsequent_person_id, applt_seq_nr, invt_seq_nr, t1.patent_office, t1.appln_filing_year, t.subsequent_date, 1, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
JOIN patstat.tls207_pers_appln t2 ON (t.subsequent_id = t2.appln_id)
ORDER BY t1.appln_id, t.subsequent_date, t2.person_id, applt_seq_nr, invt_seq_nr ASC;

DROP TABLE t;
CREATE TABLE t AS
SELECT t1.appln_id, t2.appln_id AS subsequent_id, t2.appln_filing_date AS subsequent_date
FROM PRIORITY_FILINGS_inv t1 
INNER JOIN patstat.tls201_appln t2 ON t1.appln_id = t2.internat_appln_id
WHERE type = 'pct'
AND t2.internat_appln_id != 0 and nat_phase = 'Y'
GROUP BY t1.appln_id, t2.appln_id, t2.appln_filing_date ;
CREATE INDEX t_appln_id ON t(appln_id);      

INSERT INTO subsequent_filings1
SELECT DISTINCT t1.appln_id, t.subsequent_id, t2.person_id as subsequent_person_id, applt_seq_nr, invt_seq_nr, t1.patent_office, t1.appln_filing_year, t.subsequent_date, 2, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
JOIN patstat.tls207_pers_appln t2 ON (t.subsequent_id = t2.appln_id)
ORDER BY t1.appln_id, t.subsequent_date, t2.person_id, applt_seq_nr, invt_seq_nr ASC;

DROP INDEX IF EXISTS sec1_idx, sec1_sub_idx, sec1_office_idx, sec1_year_idx, sec1_nb_prior_idx, sec1_applt_idx, sec1_invt_idx;							
CREATE INDEX sec1_idx ON SUBSEQUENT_FILINGS1 USING btree (appln_id);
CREATE INDEX sec1_sub_idx ON SUBSEQUENT_FILINGS1 USING btree (subsequent_id);
CREATE INDEX sec1_sub_pers_idx ON SUBSEQUENT_FILINGS1 USING btree (subsequent_person_id);
CREATE INDEX sec1_office_idx ON SUBSEQUENT_FILINGS1 USING btree (patent_office);
CREATE INDEX sec1_year_idx ON SUBSEQUENT_FILINGS1 USING btree (appln_filing_year);	
CREATE INDEX sec1_nb_prior_idx ON SUBSEQUENT_FILINGS1 USING btree (nb_priorities);
CREATE INDEX sec1_applt_idx ON SUBSEQUENT_FILINGS1 USING btree (applt_seq_nr);
CREATE INDEX sec1_invt_idx ON SUBSEQUENT_FILINGS1 USING btree (invt_seq_nr);
DROP TABLE t;

 
-- B.1 Information from equivalents (source = 2)
-- B.1.1 Find all the relevant information
DROP TABLE IF EXISTS EQUIVALENTS2;
CREATE  TABLE EQUIVALENTS2 AS (
SELECT  t1.appln_id,  t1.subsequent_id, t1.subsequent_person_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, ctry_code, type
FROM SUBSEQUENT_FILINGS1 t1 
JOIN country_codes_inv t2 ON (t1.subsequent_id = t2.appln_id and t1.subsequent_person_id = t2.person_id)
WHERE t1.nb_priorities = 1 AND invt_seq_nr >0 AND NULLIF(ctry_code, '') IS NOT NULL );
DROP INDEX IF EXISTS equ2_idx, equ2_sub_idx, equ2_pers_idx, equ2_office_idx, equ2_year_idx;
CREATE INDEX equ2_idx ON EQUIVALENTS2 USING btree (appln_id);
CREATE INDEX equ2_sub_idx ON EQUIVALENTS2 USING btree (subsequent_id);
CREATE INDEX equ2_sub_pers_idx ON EQUIVALENTS2 USING btree (subsequent_person_id);
CREATE INDEX equ2_office_idx ON EQUIVALENTS2 USING btree (patent_office);
CREATE INDEX equ2_year_idx ON EQUIVALENTS2 USING btree (appln_filing_year); 
 
-- B.1.2 Select the most appropriate (i.e. earliest) equivalent
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2;
CREATE  TABLE EARLIEST_EQUIVALENT2 AS 
SELECT t1.appln_id, subsequent_id, subsequent_person_id, ctry_code, type, min
FROM EQUIVALENTS2 t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM EQUIVALENTS2
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS eequ_idx, eequ_sub_idx, eequ2_sub_pers_idx;
CREATE INDEX eequ2_idx ON EARLIEST_EQUIVALENT2 USING btree (appln_id);
CREATE INDEX eequ2_sub_idx ON EARLIEST_EQUIVALENT2 USING btree (subsequent_id);
CREATE INDEX eequ2_sub_pers_idx ON EARLIEST_EQUIVALENT2 USING btree (subsequent_person_id);

-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2_;
CREATE TABLE EARLIEST_EQUIVALENT2_ AS
SELECT t1.* FROM earliest_equivalent2 t1 JOIN 
(SELECT appln_id, min(subsequent_id) 
FROM EARLIEST_EQUIVALENT2
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS eequ2_idx_, eequ2_sub_idx_, eequ2_sub_pers_idx_;
CREATE INDEX eequ2_idx_ ON EARLIEST_EQUIVALENT2_ USING btree (appln_id);
CREATE INDEX eequ2_sub_idx_ ON EARLIEST_EQUIVALENT2_ USING btree (subsequent_id);
CREATE INDEX eequ2_sub_pers_idx_ ON EARLIEST_EQUIVALENT2_ USING btree (subsequent_person_id);

-- B.2 Information from other subsequent filings (source = 3)
-- B.2.1 Find information on inventors from subsequent filings for patents that have not yet been identified via their potential equivalent(s)
DROP TABLE IF EXISTS OTHER_SUBSEQUENT_FILINGS3;
CREATE  TABLE OTHER_SUBSEQUENT_FILINGS3 AS (
SELECT  t1.appln_id,  t1.subsequent_id, t1.subsequent_person_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, ctry_code, type
FROM SUBSEQUENT_FILINGS1 t1 
JOIN country_codes_inv t2 ON (t1.subsequent_id = t2.appln_id and t1.subsequent_person_id = t2.person_id)
WHERE t1.nb_priorities > 1 AND invt_seq_nr >0 AND NULLIF(ctry_code, '') IS NOT NULL);
DROP INDEX IF EXISTS other3_idx, other3_sub_idx, other3_office_idy, other3_year_idx;
CREATE INDEX other3_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (appln_id);
CREATE INDEX other3_sub_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (subsequent_id);
CREATE INDEX other3_sub_pers_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (subsequent_person_id);
CREATE INDEX other3_office_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (patent_office);
CREATE INDEX other3_year_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (appln_filing_year);  
 
-- B.2.2 Select the most appropriate (i.e. earliest) subsequent filing
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3;
CREATE  TABLE EARLIEST_SUBSEQUENT_FILING3 AS 
SELECT t1.appln_id, subsequent_id, subsequent_person_id, ctry_code, type, min
FROM OTHER_SUBSEQUENT_FILINGS3 t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM OTHER_SUBSEQUENT_FILINGS3
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS esub3_idx, esub3_sub_idx, esub3_sub_pers_idx;
CREATE INDEX esub3_idx ON EARLIEST_SUBSEQUENT_FILING3 USING btree (appln_id);
CREATE INDEX esub3_sub_idx ON EARLIEST_SUBSEQUENT_FILING3 USING btree (subsequent_id);
CREATE INDEX esub3_sub_pers_idx ON EARLIEST_SUBSEQUENT_FILING3 USING btree (subsequent_person_id);
 
-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3_;
CREATE TABLE EARLIEST_SUBSEQUENT_FILING3_ AS
SELECT t1.* FROM EARLIEST_SUBSEQUENT_FILING3 t1 JOIN 
(SELECT appln_id, min(subsequent_id) 
FROM EARLIEST_SUBSEQUENT_FILING3
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS esub3_idx_, esub3_sub_idx_, esub3_sub_pers_idx_;
CREATE INDEX esub3_idx_ ON EARLIEST_SUBSEQUENT_FILING3_ USING btree (appln_id);
CREATE INDEX esub3_sub_idx_ ON EARLIEST_SUBSEQUENT_FILING3_ USING btree (subsequent_id);
CREATE INDEX esub3_sub_pers_idx_ ON EARLIEST_SUBSEQUENT_FILING3_ USING btree (subsequent_person_id);
 
-- Applicant information
 
-- C. Information that is directly available (source = 4)
DROP TABLE IF EXISTS PRIORITY_FILINGS4;
CREATE TABLE PRIORITY_FILINGS4 AS (
SELECT DISTINCT t1.appln_id, t1.patent_office, t1.appln_filing_year, ctry_code, type
FROM PRIORITY_FILINGS_inv t1 
JOIN country_codes_app t2 ON (t1.appln_id = t2.appln_id)
WHERE NULLIF(t2.ctry_code, '') IS NOT NULL) ;
DROP INDEX IF EXISTS pri4_idx, pri4_office_idx, pri4_year_idx;
CREATE INDEX pri4_idx ON PRIORITY_FILINGS4 USING btree (appln_id);
CREATE INDEX pri4_office_idx ON PRIORITY_FILINGS4 USING btree (patent_office);
CREATE INDEX pri4_year_idx ON PRIORITY_FILINGS4 USING btree (appln_filing_year);  

 
-- D.1 Use information from equivalents (source = 5)
-- D.1.1 Find all the relevant information
DROP TABLE IF EXISTS EQUIVALENTS5;
CREATE  TABLE EQUIVALENTS5 AS (
SELECT  t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, ctry_code, type
FROM SUBSEQUENT_FILINGS1 t1 
JOIN country_codes_app t2 ON (t1.subsequent_id = t2.appln_id)
WHERE t1.nb_priorities = 1  AND applt_seq_nr > 0 AND NULLIF(ctry_code, '') IS NOT NULL);
DROP INDEX IF EXISTS equ5_idx, equ5_sub_idx, equ5_office_idx, equ5_year_idx;
CREATE INDEX equ5_idx ON EQUIVALENTS5 USING btree (appln_id);
CREATE INDEX equ5_sub_idx ON EQUIVALENTS5  USING btree (subsequent_id);
CREATE INDEX equ5_office_idx ON EQUIVALENTS5 USING btree (patent_office);
CREATE INDEX equ5_year_idx ON EQUIVALENTS5 USING btree (appln_filing_year); 
 
-- D.1.2 Select the most appropriate (i.e. earliest) equivalent
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT5;
CREATE  TABLE EARLIEST_EQUIVALENT5 AS 
SELECT t1.appln_id, subsequent_id, ctry_code, type, min
FROM EQUIVALENTS5 t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM EQUIVALENTS5
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS eequ5_idx, eequ_sub_idx;
CREATE INDEX eequ5_idx ON EARLIEST_EQUIVALENT5 USING btree (appln_id);
CREATE INDEX eequ5_sub_idx ON EARLIEST_EQUIVALENT5 USING btree (subsequent_id);
 
-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT5_;
CREATE TABLE EARLIEST_EQUIVALENT5_ AS
SELECT t1.* FROM earliest_equivalent5 t1 JOIN 
(SELECT appln_id, min(subsequent_id) 
FROM EARLIEST_EQUIVALENT5
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min
;
DROP INDEX IF EXISTS eequ5_idx_, eequ_sub_idx_;
CREATE INDEX eequ5_idx_ ON EARLIEST_EQUIVALENT5_ USING btree (appln_id);
CREATE INDEX eequ5_sub_idx_ ON EARLIEST_EQUIVALENT5_ USING btree (subsequent_id);
 
-- D.2 Use information from other subsequent filings (source = 6)
-- D.2.1 Find information on inventors from subsequent filings for patents that have not yet been identified via their potential equivalents
DROP TABLE IF EXISTS OTHER_SUBSEQUENT_FILINGS6;
CREATE TABLE OTHER_SUBSEQUENT_FILINGS6 AS (
SELECT  t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, ctry_code, type 
FROM SUBSEQUENT_FILINGS1 t1 
JOIN country_codes_app t2 ON (t1.subsequent_id = t2.appln_id)
WHERE t1.nb_priorities > 1  AND applt_seq_nr > 0 AND NULLIF(ctry_code, '') IS NOT NULL );
DROP INDEX IF EXISTS other6_idx, other6_sub_idx, other6_office_idx, other6_year_idx, other6_sub_pers_idx;
CREATE INDEX other6_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (appln_id);
CREATE INDEX other6_sub_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (subsequent_id);
CREATE INDEX other6_office_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (patent_office);
CREATE INDEX other6_year_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (appln_filing_year); 
 
-- D.2.2 Select the most appropriate (i.e. earliest) subsequent filing
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING6;
CREATE  TABLE EARLIEST_SUBSEQUENT_FILING6 AS 
SELECT t1.appln_id, subsequent_id, ctry_code, type, min
FROM OTHER_SUBSEQUENT_FILINGS6 t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM OTHER_SUBSEQUENT_FILINGS6
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS esub6_idx, esub6_sub_idx;
CREATE INDEX esub6_idx ON EARLIEST_SUBSEQUENT_FILING6 USING btree (appln_id);
CREATE INDEX esub6_sub_idx ON EARLIEST_SUBSEQUENT_FILING6 USING btree (subsequent_id);
 
-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING6_;
CREATE TABLE EARLIEST_SUBSEQUENT_FILING6_ AS
SELECT t1.* FROM EARLIEST_SUBSEQUENT_FILING6 t1 JOIN 
(SELECT appln_id, min(subsequent_id) 
FROM EARLIEST_SUBSEQUENT_FILING6
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min
;
DROP INDEX IF EXISTS esub6_idx_, esub6_sub_idx_;
CREATE INDEX esub6_idx_ ON EARLIEST_SUBSEQUENT_FILING6_ USING btree (appln_id);
CREATE INDEX esub6_sub_idx_ ON EARLIEST_SUBSEQUENT_FILING6_ USING btree (subsequent_id);
 
-- table containing the information on priority filings and country information if available for priority filing
DROP TABLE IF EXISTS TABLE_INV;
CREATE TABLE TABLE_INV AS
SELECT * FROM priority_filings1; 
 
CREATE INDEX TABLE_INV_APPLN_ID ON TABLE_INV USING btree (appln_id);
CREATE INDEX TABLE_INV_PERSON_ID ON TABLE_INV USING btree (person_id);
 
DROP TABLE IF EXISTS TABLE_TO_BE_FILLED_INV;
CREATE  TABLE TABLE_TO_BE_FILLED_INV (
appln_id INTEGER DEFAULT NULL,
person_id INTEGER DEFAULT NULL,
ctry_code VARCHAR(2) DEFAULT NULL,
source SMALLINT DEFAULT NULL,
type TEXT DEFAULT NULL
);
 
 
 
 
/* 
  MAIN PROCEDURE
*/
 

-- A Insert information that is directly available (source = 1)
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT  t_.appln_id, t_.person_id, ctry_code, 1, type
FROM TABLE_INV t_
WHERE NULLIF(t_.ctry_code, '') IS NOT NULL;
 
CREATE INDEX TABLE_TO_BE_FILLED_INV_appln_id ON TABLE_TO_BE_FILLED_INV(appln_id);
 
-- delete information that has been added
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);                
 
-- B.1 Add the information from each selected equivalent
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.subsequent_person_id,
t_.ctry_code,
2,
t_.type
FROM (
SELECT t1.appln_id, t1.subsequent_person_id, ctry_code, type
FROM EARLIEST_EQUIVALENT2_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE NULLIF(t1.ctry_code, '') IS NOT NULL 
) AS t_
;
 
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);                
 
-- B.2 Add the information from each selected subsequent filing
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.subsequent_person_id,
t_.ctry_code,
3,
t_.type 
FROM (
SELECT t1.appln_id, t1.subsequent_person_id, ctry_code, type
FROM EARLIEST_SUBSEQUENT_FILING3_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE NULLIF(t1.ctry_code, '') IS NOT NULL 
) AS t_
;
 
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);  
 
-- Take information from applicants to recover missing information 
 
-- C Insert information that is directly available (source = 4)
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
0,
t_.ctry_code,
4,
t_.type
FROM (
SELECT t1.appln_id, ctry_code, type
FROM PRIORITY_FILINGS4 t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE NULLIF(t1.ctry_code, '') IS NOT NULL 
) AS t_
;
 
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);  
 
-- D.1 Add the information from each selected equivalent
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
0,
t_.ctry_code,
5,
t_.type   
FROM (
SELECT t1.appln_id, ctry_code, type
FROM EARLIEST_EQUIVALENT5_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE NULLIF(t1.ctry_code, '') IS NOT NULL 
) AS t_
;
 
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);  
 
-- D.2 Add the information from each selected subsequent filing
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
0,
t_.ctry_code,
6,
t_.type
FROM (
SELECT t1.appln_id, ctry_code, type
FROM EARLIEST_SUBSEQUENT_FILING6_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE NULLIF(t1.ctry_code, '') IS NOT NULL 
) AS t_
;
 
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);
 
-- E. If country code is still missing, set it equal to a filing's patent office
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
0,
t_.patent_office,
7,
t_.type
FROM (
SELECT t1.appln_id, patent_office, type
FROM PRIORITY_FILINGS_inv t1 
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON (t1.appln_id = t2.appln_id) 
WHERE patent_office NOT IN ('EP', 'AP', 'EA', 'GC', 'OA', 'WO')
) AS t_  ;
 
-- Table with location information from all possible sources
DROP TABLE IF EXISTS PF_INV_PERS_CTRY_ALL;
CREATE TABLE PF_INV_PERS_CTRY_ALL (
appln_id INTEGER DEFAULT NULL,
person_id INTEGER DEFAULT NULL,
patent_office CHAR(2) DEFAULT NULL,
priority_date date DEFAULT NULL,
priority_year INTEGER DEFAULT NULL,
ctry_code TEXT DEFAULT NULL,
source SMALLINT DEFAULT NULL,
type TEXT DEFAULT NULL
); COMMENT ON TABLE PF_INV_PERS_CTRY_ALL IS 'Inventors from priority filings of a given (po, year)';
 
-- F. Job done, insert into final table 
INSERT INTO PF_INV_PERS_CTRY_ALL
SELECT t1.appln_id, t1.person_id, t2.patent_office, t2.appln_filing_date, t2.appln_filing_year, ctry_code, source, type
FROM TABLE_TO_BE_FILLED_INV t1 JOIN (
SELECT DISTINCT appln_id, patent_office, appln_filing_date, appln_filing_year FROM PRIORITY_FILINGS_inv) AS t2 ON t1.appln_id = t2.appln_id;
 
CREATE INDEX PF_INV_PERS_CTRY_ALL_APPLN_ID ON PF_INV_PERS_CTRY_ALL(appln_id);
CREATE INDEX PF_INV_PERS_CTRY_ALL_PERS_ID ON PF_INV_PERS_CTRY_ALL(person_id);
CREATE INDEX PF_INV_PERS_CTRY_ALL_YEAR ON PF_INV_PERS_CTRY_ALL(priority_year);
 
 
ALTER TABLE PF_INV_PERS_CTRY_ALL ADD COLUMN lastupdate TIMESTAMP; 
UPDATE PF_INV_PERS_CTRY_ALL SET lastupdate = CURRENT_TIMESTAMP;  
  
 
 
ALTER TABLE pf_inv_pers_ctry_all ADD COLUMN country VARCHAR; 
UPDATE pf_inv_pers_ctry_all SET country = 
CASE
WHEN ctry_code ='AU' THEN 'Australia'
WHEN ctry_code ='AT' THEN 'Austria'
WHEN ctry_code ='BE' THEN 'Belgium'
WHEN ctry_code ='BR' THEN 'Brazil'
WHEN ctry_code ='BG' THEN 'Bulgaria'
WHEN ctry_code ='CA' THEN 'Canada'
WHEN ctry_code ='CL' THEN 'Chile'
WHEN ctry_code ='CN' THEN 'China'
WHEN ctry_code ='HR' THEN 'Croatia'
WHEN ctry_code ='CZ' THEN 'Czech Republic'
WHEN ctry_code ='DK' THEN 'Denmark'
WHEN ctry_code ='EE' THEN 'Estonia'
WHEN ctry_code ='FI' THEN 'Finland'
WHEN ctry_code ='FR' THEN 'France'
WHEN ctry_code ='DE' THEN 'Germany'
WHEN ctry_code ='GR' THEN 'Greece'
WHEN ctry_code ='HU' THEN 'Hungary'
WHEN ctry_code ='IS' THEN 'Iceland'
WHEN ctry_code ='IN' THEN 'India'
WHEN ctry_code ='IE' THEN 'Ireland'
WHEN ctry_code ='IL' THEN 'Israel'
WHEN ctry_code ='IT' THEN 'Italy'
WHEN ctry_code ='JP' THEN 'Japan'
WHEN ctry_code ='KR' THEN 'South Korea'
WHEN ctry_code ='LV' THEN 'Latvia'
WHEN ctry_code ='MT' THEN 'Malta'
WHEN ctry_code ='MX' THEN 'Mexico'
WHEN ctry_code ='NL' THEN 'Netherlands'
WHEN ctry_code ='NZ' THEN 'New Zealand'
WHEN ctry_code ='NO' THEN 'Norway'
WHEN ctry_code ='PL' THEN 'Poland'
WHEN ctry_code ='PT' THEN 'Portugal'
WHEN ctry_code ='RO' THEN 'Romania'
WHEN ctry_code ='RU' THEN 'Russia'
WHEN ctry_code ='SK' THEN 'Slovakia'
WHEN ctry_code ='SI' THEN 'Slovenia'
WHEN ctry_code ='ZA' THEN 'South Africa'
WHEN ctry_code ='ES' THEN 'Spain'
WHEN ctry_code ='SE' THEN 'Sweden'
WHEN ctry_code ='CH' THEN 'Switzerland'
WHEN ctry_code ='TR' THEN 'Turkey'
WHEN ctry_code ='GB' THEN 'United Kingdom'
WHEN ctry_code ='US' THEN 'United States'
WHEN ctry_code ='LU' THEN 'Luxembourg'
WHEN ctry_code ='LT' THEN 'Lithuania'
WHEN ctry_code ='LI' THEN 'Liechtenstein'
WHEN ctry_code ='HK' THEN 'Hong Kong'
END  ;
 
CREATE INDEX PF_INV_PERS_CTRY_ALL_COUNTRY ON PF_INV_PERS_CTRY_ALL(country);
 

\COPY (SELECT * FROM pf_inv_pers_ctry_all ORDER BY appln_id) TO 'C:\Users\seligerf\Dropbox (KOF)\KOF''s shared workspace\01 Projects(funded)\FBI.FP.91 - Globalisation of R&D - Technology Clusters\Daten\data_repository\ctry_inv_person.txt' CSV HEADER NULL '' DELIMITER ',' ENCODING 'UTF8'; 
 
DROP TABLE if exists po;
--DROP TABLE if exists toExclude;
DROP TABLE if exists PRIORITY_FILINGS_INV;
DROP TABLE if exists TABLE_TO_BE_FILLED_INV;
DROP TABLE if exists TABLE_INV;
DROP table if exists country_codes_app;
DROP table if exists country_codes_inv;
DROP table if exists PRIORITY_FILINGS1;
DROP table if exists SUBSEQUENT_FILINGS1;
DROP table if exists EQUIVALENTS2;
DROP table if exists EARLIEST_EQUIVALENT2;
DROP table if exists EARLIEST_EQUIVALENT2_;
DROP table if exists OTHER_SUBSEQUENT_FILINGS3;
DROP table if exists EARLIEST_SUBSEQUENT_FILING3;
DROP table if exists EARLIEST_SUBSEQUENT_FILING3_;
DROP table if exists PRIORITY_FILINGS4;
DROP table if exists EQUIVALENTS5;
DROP table if exists EARLIEST_EQUIVALENT5;
DROP table if exists EARLIEST_EQUIVALENT5_;
DROP table if exists OTHER_SUBSEQUENT_FILINGS6;
DROP table if exists EARLIEST_SUBSEQUENT_FILING6;
DROP table if exists EARLIEST_SUBSEQUENT_FILING6_;