/***************************************************************************************************************************

  Algorithm to impute missing geographic information of first filings by inventors from subsequent filings
  
  This code builds on the work of: G. de Rassenfosse (University of Melbourne, Australia)
  It was written by Florian Seliger in February 2019 using PostgreSQL and Patstat Spring 2019 (and location information from Patstat Autumn 2016).

  Please acknowledge the work and cite the companion papers:
  - de Rassenfosse, G., Dernis, H., Guellec, D., Picci, L., van Pottelsberghe de la Potterie, B., 2013. 
    The worldwide count of priority patents: A new indicator of inventive activity. Research Policy
  - de Rassenfosse, G., Kozak, J., Seliger, F., 2019. Geocoding of worldwide patent data. Manuscript
  
  Florian Seliger would like to thank Charles Clavadetscher (KOF ETHZ) and Matthias Bannert (KOF ETHZ) for their help.

  Description : PostgreSQL code to impute missing geographic information (coordinates, city and regional information) for first filings based on the inventor criterion. 
  When the information on inventors' locations is missing, the algorithm looks into direct equivalents and other subsequent filings for the information. 
  Information can also be retrieved from applicants' location.


  Output: table PF_INV_GEOC. The field 'source' indicates where the information on 
  inventors' location comes from : 	1 = information available from the patent itself
                        			2 = information availabe from the earliest direct equivalent
                        			3 = information available from the earliest subsequent filing
                            		4 = applicants' location from the patent itself 
                            		5 = applicants' location from earliest direct equivalent
                            		6 = applicants' information from earliest subsequent filing
                        
  The following 52 patent offices are browsed (EU27 + OECD + BRICS + EPO + WIPO): 
  AL,AT,AU,BE,BG,BR,CA,CH,CL,CN,CY,CZ,DE,DK,EE,EP,ES,FI,FR,GB,GR,HR, HU,IB,IE,IL,IN,IS,IT,JP,KR,LT,LU,LV,MK,MT,MX,NL,NO,NZ,PL,PT,RO,RS,RU,SE,SI,SK,SM,TR,US,ZA.

******************************************************************************************/

/*
  CREATE ALL TABLES NEEDED
*/

--create addresses_coordinates_all, add exact coordinates, and replenish null results with information from geonames (null results appear when the geocoding failed or when the result has been discarded) 
DROP TABLE IF EXISTS addresses_coordinates_all;
CREATE TABLE addresses_coordinates_all AS
SELECT t1.*, t2.lat_exact, t2.lng_exact FROM addresses_googleresponse_all t1
LEFT OUTER JOIN exact_coordinates_patstatregpat t2 ON t1.unformattedaddress = t2.unformattedaddress;

UPDATE addresses_coordinates_all t1 SET 
lat_exact = t2.lat_exact,
lng_exact = t2.lng_exact
FROM exact_coordinates_other t2
WHERE t1.unformattedaddress = t2.unformattedaddress;

UPDATE addresses_coordinates_all t1 SET 
lat_exact = t2.lat_exact,
lng_exact = t2.lng_exact
FROM exact_coordinates_pct t2
WHERE t1.unformattedaddress = t2.address_text;

CREATE TABLE addresses_coordinates_all_uspto AS
SELECT t1.*, t2.latitude, t2.longitude FROM addresses_googleresponse_all t1
JOIN public2.location_uspto t2 ON t1.formattedaddress = t2.city
WHERE data_source = 'USPTO';

CREATE INDEX addresses_coordinates_all_unformattedaddress
ON addresses_coordinates_all (unformattedaddress);
CREATE INDEX addresses_coordinates_all_uspto_unformattedaddress 
ON addresses_coordinates_all_uspto(unformattedaddress);

UPDATE addresses_coordinates_all t1 SET
lat_exact = t2.latitude::DECIMAL,
lng_exact = t2.longitude::DECIMAL
FROM addresses_coordinates_all_uspto AS t2
WHERE t1.unformattedaddress = t2.unformattedaddress;

DROP TABLE addresses_coordinates_all_uspto;
DELETE FROM addresses_coordinates_all WHERE unformattedaddress IS NULL AND data_source = 'USPTO';

ALTER TABLE addresses_coordinates_all ADD COLUMN coord_source TEXT;
UPDATE addresses_coordinates_all t1 SET
lat = lat_geon,
lng = lng_geon,
lat_exact = lat_geon::DECIMAL,
lng_exact = lng_geon::DECIMAL,
country = country_geon,
coord_source = 'geonames' 
WHERE numresults = 0 AND match_geon IS NOT NULL;


--add location_id from processed address data by name matching
ALTER TABLE addresses_coordinates_all DROP COLUMN location_id;
DROP TABLE IF EXISTS addresses_coordinates_all_;
CREATE TABLE addresses_coordinates_all_ AS (
SELECT t2.location_id, t1.unformattedaddress, t1.country, t1.locality, t1.administrative_area_level_1, t1.administrative_area_level_2, t1.administrative_area_level_3, 
  t1.administrative_area_level_4, t1.administrative_area_level_5, t1.country_geon, t1.admin_name1, t1.admin_name2, t1.admin_name3, t1.admin_name4, 
  t1.coord_source, t1.lat_exact, t1.lng_exact, t1.lat, t1.lng, t1.viewportArea, t1.data_source
FROM addresses_coordinates_all t1
--addresses contains all cleaned address information from Patstat
LEFT OUTER JOIN public2.addresses t2 ON t1.unformattedaddress = t2.unformattedaddress
);
CREATE INDEX unformatted_address_idx_
ON addresses_coordinates_all_ (unformattedaddress);
CREATE INDEX addresses_coordinates_all_location_id_
ON addresses_coordinates_all_ (location_id);
--inventor_applicant_all contains cleaned address information from all other patent offices
UPDATE addresses_coordinates_all_ t1 
SET location_id = t3.location_id FROM inventor_applicant_location_id t3 WHERE substring(t1.unformattedaddress, 1, length(t1.unformattedaddress) - 4) = t3.address_ 
and t1.location_id is null and length(t1.unformattedaddress) >= 4;

--add further location ids from inventor_applicant_location_id
drop table if exists further_location_ids;
create table further_location_ids as (
select t3.location_id, t1.unformattedaddress, t1.country, t1.locality, t1.administrative_area_level_1, t1.administrative_area_level_2, t1.administrative_area_level_3, 
  t1.administrative_area_level_4, t1.administrative_area_level_5, t1.country_geon, t1.admin_name1, t1.admin_name2, t1.admin_name3, t1.admin_name4, 
  t1.coord_source, t1.lat_exact, t1.lng_exact, t1.lat, t1.lng, t1.viewportArea, t1.data_source
from addresses_coordinates_all_ t1 
join inventor_applicant_location_id t3 on substring(t1.unformattedaddress, 1, length(t1.unformattedaddress) - 4) = t3.address_ 
where length(t1.unformattedaddress) >= 4 and t1.location_id != t3.location_id);
update further_location_ids set data_source = 'EU';

insert into addresses_coordinates_all_
select * from further_location_ids;
drop table further_location_ids;

UPDATE addresses_coordinates_all_ t1 
SET location_id = t3.location_id FROM inventor_applicant_location_id_jp t3 WHERE substring(t1.unformattedaddress, 1, length(t1.unformattedaddress) - 4) = t3.address_
and length(t1.unformattedaddress) >= 4;
UPDATE addresses_coordinates_all_ t1 
SET location_id = t3.location_id FROM inventor_applicant_location_id_kr t3 WHERE substring(t1.unformattedaddress, 1, length(t1.unformattedaddress) - 4) = t3.address_
and length(t1.unformattedaddress) >= 4;
UPDATE addresses_coordinates_all_ t1 
SET location_id = t3.location_id FROM inventor_applicant_location_id_cn t3 WHERE substring(t1.unformattedaddress, 1, length(t1.unformattedaddress) - 4) = t3.address_
and length(t1.unformattedaddress) >= 4;

DROP TABLE addresses_coordinates_all;
ALTER TABLE addresses_coordinates_all_ RENAME TO addresses_coordinates_all;

CREATE INDEX unformatted_address_idx
ON addresses_coordinates_all (unformattedaddress);
DROP INDEX addresses_coordinates_all_location_id_;


--assign country name, admin levels and locality from Google and geonames 
ALTER TABLE addresses_coordinates_all ADD COLUMN country_googlegeon VARCHAR, ADD COLUMN city VARCHAR, ADD COLUMN admin_level VARCHAR, ADD COLUMN sub_admin_level VARCHAR, ADD COLUMN subsub_admin_level VARCHAR;

--Google information
UPDATE addresses_coordinates_all 
SET country_googlegeon = country,
city = locality,
admin_level = administrative_area_level_1,
sub_admin_level = administrative_area_level_2,
subsub_admin_level = administrative_area_level_3;

--geonames information
UPDATE addresses_coordinates_all
SET country_googlegeon = country_geon
WHERE country_googlegeon IS NULL AND country_geon IS NOT NULL;

UPDATE addresses_coordinates_all
SET city = admin_name1
WHERE city IS NULL AND admin_name1 IS NOT NULL;

UPDATE addresses_coordinates_all 
SET admin_level = admin_name2
WHERE admin_level IS NULL AND admin_name2 IS NOT NULL;

UPDATE addresses_coordinates_all 
SET sub_admin_level = admin_name3
WHERE sub_admin_level IS NULL AND admin_name3 IS NOT NULL;

UPDATE addresses_coordinates_all 
SET subsub_admin_level = admin_name4
WHERE subsub_admin_level IS NULL AND admin_name4 IS NOT NULL;

UPDATE addresses_coordinates_all SET coord_source = 'geolocalization' WHERE coord_source IS NULL;


--add PostGIS geometry
ALTER TABLE addresses_coordinates_all ADD COLUMN geom GEOMETRY;
UPDATE addresses_coordinates_all SET geom = (ST_SetSRID(ST_MakePoint(lng_exact,lat_exact),4326)) ;
CREATE INDEX addresses_coordinates_all_gix ON addresses_coordinates_all USING GIST (geom);
--convert data to be in meters
ALTER TABLE addresses_coordinates_all ADD COLUMN geom_m GEOMETRY;
UPDATE addresses_coordinates_all SET geom_m = ST_TRANSFORM(geom, 5243) ;
--CREATE INDEX gix_m ON addresses_coordinates_all USING GIST (geom_m);

--add country and region information from GADM data
ALTER TABLE addresses_coordinates_all ADD COLUMN name_0 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN name_1 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN name_2 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN name_3 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN name_4 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN name_5 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN engtype_1 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN engtype_2 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN engtype_3 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN engtype_4 TEXT;
ALTER TABLE addresses_coordinates_all ADD COLUMN engtype_5 TEXT;
UPDATE addresses_coordinates_all t1 SET 
name_0 = t2.name_0,
name_1 = t2.name_1,
name_2 = t2.name_2,
name_3 = t2.name_3,
name_4 = t2.name_4,
name_5 = t2.name_5,
engtype_1 = t2.engtype_1,
engtype_2 = t2.engtype_2,
engtype_3 = t2.engtype_3,
engtype_4 = t2.engtype_4,
engtype_5 = t2.engtype_5 
FROM geodata.admin_levels t2
WHERE ST_Within(t1.geom, t2.geom) ;

DROP INDEX addresses_coordinates_all_gix; -- needs to be recreated on final dataset later

-- the city column will be filled later
ALTER TABLE addresses_coordinates_all ADD COLUMN city_from_shapefile TEXT;

--------------------------------------------------------------------------------------------------------------------


  -- table containing the patent offices to browse
DROP TABLE IF EXISTS po;
CREATE TABLE po (
patent_office CHAR(2) DEFAULT NULL
) ; COMMENT ON TABLE po IS 'List of patent offices to browse';
INSERT INTO po VALUES ('AL'), ('AT'), ('AU'), ('BE'), ('BG'),('BR'), ('CA'), ('CH'), ('CL'), ('CN'),('CY'), ('CZ'), ('DE'), ('DK'), ('EE'), ('EP'), ('ES'), ('FI'), ('FR'), ('GB'), ('GR'), ('HR'), ('HU'), ('IB'), ('IE'),   ('IL'), ('IN'), ('IS'), ('IT'), ('JP'), ('KR'), ('LT'), ('LU'), ('LV'), ('MK'), ('MT'), ('MX'), ('NL'), ('NO'), ('NZ'), ('PL'), ('PT'), ('RO'), ('RS'), ('RU'), ('SE'), ('SI'), ('SK'), ('SM'), ('TR'), ('US'), ('ZA');
DROP INDEX IF EXISTS po_idx;
CREATE INDEX po_idx ON po USING btree (patent_office);

-- table containing the appln_id to exclude from the analysis (e.g. petty patents) for a given patent office

DROP TABLE IF EXISTS toExclude;
CREATE  TABLE toExclude AS
SELECT DISTINCT appln_id, publn_auth, publn_kind FROM patstat.tls211_pat_publn
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
; COMMENT ON TABLE toExclude IS 'Excluded appln_id for a given po based on publn_kind';
DROP INDEX IF EXISTS exclude_idx;
CREATE INDEX exclude_idx ON toExclude USING btree (appln_id);



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


INSERT INTO PRIORITY_FILINGS_INV
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'priority'
FROM patstat.tls201_appln t1 
JOIN patstat.tls204_appln_prior t2 ON t1.appln_id = t2.prior_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'priority'
FROM patstat.tls201_appln t1 
JOIN patstat.tls204_appln_prior t2 ON t1.appln_id = t2.prior_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016;


 
INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t7.person_id, t1.appln_auth AS patent_office, t1.appln_filing_year, t1.appln_filing_date, 'pct'
FROM patstat.tls201_appln t1 
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON (t1.receiving_office = t5.patent_office)
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id

  LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0 and nat_phase = 'N' and reg_phase = 'N'
AND t1.appln_id = t1.earliest_filing_id
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;


INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'continual'
FROM patstat.tls201_appln t1 
JOIN patstat.tls216_appln_contn t2 ON t1.appln_id = t2.parent_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id

    LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'continual'
FROM patstat.tls201_appln t1 
JOIN patstat.tls216_appln_contn t2 ON t1.appln_id = t2.parent_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'tech_rel'
FROM patstat.tls201_appln t1 
JOIN patstat.tls205_tech_rel t2 ON t1.appln_id = t2.tech_rel_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'tech_rel'
FROM patstat.tls201_appln t1 
JOIN patstat.tls205_tech_rel t2 ON t1.appln_id = t2.tech_rel_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

-- Singletons
CREATE INDEX tls201_appln_docdb_family_id on patstat.tls201_appln(docdb_family_id);
INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'single'
FROM patstat.tls201_appln t1 
JOIN (SELECT docdb_family_id from patstat.tls201_appln group by docdb_family_id having count(distinct appln_id) = 1) as t2
ON t1.docdb_family_id = t2.docdb_family_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS_inv 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t6.person_id, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'single'
FROM patstat.tls201_appln t1 
JOIN (SELECT docdb_family_id from patstat.tls201_appln group by docdb_family_id having count(distinct appln_id) = 1) as t2
ON t1.docdb_family_id = t2.docdb_family_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.receiving_office = t5.patent_office
JOIN patstat.tls207_pers_appln t6 ON t1.appln_id = t6.appln_id
      LEFT OUTER JOIN PRIORITY_FILINGS_inv t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND invt_seq_nr > 0
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;



DROP INDEX IF EXISTS pf_idx, pf_idx2, pf_idx3, pf_idx4;
CREATE INDEX pf_idx ON PRIORITY_FILINGS_inv USING btree (appln_id);
CREATE INDEX pf_idx2 ON PRIORITY_FILINGS_inv USING btree (patent_office);
CREATE INDEX pf_idx3 ON PRIORITY_FILINGS_inv USING btree (appln_filing_year);
CREATE INDEX pf_idx4 ON PRIORITY_FILINGS_inv USING btree (person_id);








-- Table containing appln_id, country, region, coordinates for inventors and applicants, respectively 
CREATE INDEX addresses_coordinates_all_location_id ON addresses_coordinates_all (location_id);
CREATE INDEX addresses_coordinates_all_data_source ON addresses_coordinates_all (data_source);
 
DROP TABLE IF EXISTS addresses_coordinates_all_inv;
CREATE TABLE addresses_coordinates_all_inv AS
SELECT DISTINCT t1.unformattedaddress, t3.appln_id, t3.person_id, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea, t1.data_source,
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN public2.person_location_id t2 ON t1.location_id = t2.location_id
JOIN patstat.tls207_pers_appln t3 ON t2.person_id = t3.person_id
WHERE data_source IN ('PATSTATREGPAT', 'USPTO')
AND invt_seq_nr > 0;


-- CREATE INDEX addresses_googleresponse_pct_temp_address_text_idx ON addresses_googleresponse_pct_temp(address_text);
-- CREATE INDEX addresses_googleresponse_pct_temp_relation_type_idx ON addresses_googleresponse_pct_temp(relation_type_id);
CREATE INDEX addresses_coordinates_all_inv_unformattedaddress_idx ON addresses_coordinates_all_inv(unformattedaddress);

INSERT INTO addresses_coordinates_all_inv
SELECT DISTINCT t1.unformattedaddress, t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN addresses_googleresponse_pct_temp t2 ON t1.unformattedaddress = t2.address_text
WHERE data_source IN ('PCT', 'PATSTATREGPAT', 'USPTO')
AND relation_type_id = 4 OR relation_type_id = 7 OR relation_type_id = 6;
ALTER TABLE addresses_coordinates_all_inv DROP COLUMN unformattedaddress;


CREATE TABLE INSERT_EU AS
SELECT DISTINCT t1.location_id, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level, t1.coord_source FROM addresses_coordinates_all t1 WHERE data_source IN ('EU')
;
CREATE INDEX INSERT_EU_LOCATION_ID ON INSERT_EU(location_id);

INSERT INTO addresses_coordinates_all_inv
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM INSERT_EU t1
JOIN inventor_applicant_location_id t2 ON t1.location_id = t2.location_id
AND APP_INV = 'INV';

INSERT INTO addresses_coordinates_all_inv
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea, t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN inventor_applicant_location_id_JP t2 ON t1.location_id = t2.location_id
WHERE data_source IN ('JP')
AND APP_INV = 'INV';

INSERT INTO addresses_coordinates_all_inv
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea, t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN inventor_applicant_location_id_KR t2 ON t1.location_id = t2.location_id
WHERE data_source IN ('KR')
AND APP_INV = 'INV';

DROP TABLE IF EXISTS addresses_coordinates_all_app;
CREATE TABLE addresses_coordinates_all_app AS
SELECT DISTINCT t1.unformattedaddress, t3.appln_id, t3.person_id, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m,            t1.viewportArea, t1.data_source,
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN public2.person_location_id t2 ON t1.location_id = t2.location_id
JOIN patstat.tls207_pers_appln t3 ON t2.person_id = t3.person_id
WHERE data_source IN ('PATSTATREGPAT', 'USPTO')
AND applt_seq_nr > 0;

CREATE INDEX addresses_coordinates_all_app_unformattedaddress_idx ON addresses_coordinates_all_app(unformattedaddress);

INSERT INTO addresses_coordinates_all_app
SELECT DISTINCT t1.unformattedaddress, t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN addresses_googleresponse_pct_temp t2 ON t1.unformattedaddress = t2.address_text
WHERE data_source IN ('PCT', 'PATSTATREGPAT', 'USPTO')
AND relation_type_id = 1 OR relation_type_id = 7 ;				
ALTER TABLE addresses_coordinates_all_app DROP COLUMN unformattedaddress;			

INSERT INTO addresses_coordinates_all_app
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM INSERT_EU t1
JOIN inventor_applicant_location_id t2 ON t1.location_id = t2.location_id
AND APP_INV = 'APP';

INSERT INTO addresses_coordinates_all_app
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN inventor_applicant_location_id_JP t2 ON t1.location_id = t2.location_id
WHERE data_source IN ('JP')
AND APP_INV = 'APP';

INSERT INTO addresses_coordinates_all_app
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN inventor_applicant_location_id_CN t2 ON t1.location_id = t2.location_id
WHERE data_source IN ('CN')
AND APP_INV = 'APP';

INSERT INTO addresses_coordinates_all_app
SELECT DISTINCT t2.appln_id, 0, t1.name_0, t1.name_1, t1.name_2, t1.name_3, t1.name_4, t1.name_5, t1.engtype_1, t1.engtype_2, t1.engtype_3, t1.engtype_4, t1.engtype_5, t1.lng_exact, t1.lat_exact, t1.lng, t1.lat, t1.geom, t1.geom_m, t1.viewportArea,  t1.data_source, 
t1.country_googlegeon, t1.city AS city_googlegeon, t1.admin_level, t1.sub_admin_level, t1.subsub_admin_level,
t1.coord_source FROM addresses_coordinates_all t1
JOIN inventor_applicant_location_id_KR t2 ON t1.location_id = t2.location_id
WHERE data_source IN ('KR')
AND APP_INV = 'APP';

DROP TABLE INSERT_EU;
CREATE INDEX addresses_coordinates_all_app_appln_id ON addresses_coordinates_all_app USING btree (appln_id);
CREATE INDEX addresses_coordinates_all_inv_appln_id ON addresses_coordinates_all_inv USING btree (appln_id);
CREATE INDEX addresses_coordinates_all_app_person_id ON addresses_coordinates_all_app USING btree (person_id);
CREATE INDEX addresses_coordinates_all_inv_person_id ON addresses_coordinates_all_inv USING btree (person_id);




/* 
Create the tables that will be used in main function to impute missing information
*/

--Inventor information
-- A. Information that is directly available (source = 1)
DROP TABLE IF EXISTS PRIORITY_FILINGS1;
CREATE TABLE PRIORITY_FILINGS1 AS (
-- first of all we need all priority filings with address information in Patstat and lat/lng information (person_id available)
SELECT DISTINCT t1.appln_id, t1.person_id, t1.patent_office, t1.appln_filing_year, 
name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat_exact, lng_exact, lat, lng, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM PRIORITY_FILINGS_inv t1 
JOIN addresses_coordinates_all_inv t2 ON t1.appln_id = t2.appln_id AND t1.person_id = t2.person_id AND t2.lat IS NOT NULL) ;

-- second, we need all priority filings with address information from other sources and lat/lng information (in other sources there is no person_id->person_id=0)
--CREATE INDEX addresses_coordinates_all_inv_lat ON addresses_coordinates_all_inv (lat);
drop table if exists t;
CREATE TABLE t AS
SELECT DISTINCT t1.appln_id, t1.patent_office, t1.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat_exact, lng_exact, lat, lng, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM PRIORITY_FILINGS_inv t1 
JOIN addresses_coordinates_all_inv t2 ON t1.appln_id = t2.appln_id  
WHERE t2.person_id = 0 AND t2.lat IS NOT NULL;

INSERT INTO PRIORITY_FILINGS1  
SELECT appln_id, 0, patent_office, appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat_exact, lng_exact, lat, lng, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM  t ;
-- later on, we are looking in subsequent filings for information when no address information is available in Patstat or lat/lng is missing due to NULL results
DROP TABLE t;

DROP INDEX IF EXISTS pri1_idx, pri1_pers_idx, pri1_office_idx, pri1_year_idx, priority_filings1_lat;
CREATE INDEX pri1_idx ON PRIORITY_FILINGS1 USING btree (appln_id);
CREATE INDEX pri1_pers_idx ON PRIORITY_FILINGS1 USING btree (person_id);
CREATE INDEX pri1_office_idx ON PRIORITY_FILINGS1 USING btree (patent_office);
CREATE INDEX pri1_year_idx ON PRIORITY_FILINGS1 USING btree (appln_filing_year);
CREATE INDEX priority_filings1_lat ON PRIORITY_FILINGS1 (lat_exact);


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
SELECT DISTINCT t1.appln_id, t.subsequent_id, t1.patent_office, t1.appln_filing_year, t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
ORDER BY t1.appln_id, t.subsequent_date ASC);

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
SELECT DISTINCT t1.appln_id, t.subsequent_id, t1.patent_office, t1.appln_filing_year, t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
ORDER BY t1.appln_id, t.subsequent_date ASC;

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
SELECT DISTINCT t1.appln_id, t.subsequent_id, t1.patent_office, t1.appln_filing_year, t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
ORDER BY t1.appln_id, t.subsequent_date ASC;

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
SELECT DISTINCT t1.appln_id, t.subsequent_id, t1.patent_office, t1.appln_filing_year, t.subsequent_date, 1, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
ORDER BY t1.appln_id, t.subsequent_date ASC;

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
SELECT DISTINCT t1.appln_id, t.subsequent_id, t1.patent_office, t1.appln_filing_year, t.subsequent_date, 2, type
FROM PRIORITY_FILINGS_inv t1 
JOIN t ON (t1.appln_id = t.appln_id )
ORDER BY t1.appln_id, t.subsequent_date ASC;


DROP INDEX IF EXISTS sec1_idx, sec1_office_idx, sec1_year_idx;							
CREATE INDEX sec1_idx ON SUBSEQUENT_FILINGS1 USING btree (appln_id);
CREATE INDEX sec1_sub_idx ON SUBSEQUENT_FILINGS1 USING btree (subsequent_id);
CREATE INDEX sec1_office_idx ON SUBSEQUENT_FILINGS1 USING btree (patent_office);
CREATE INDEX sec1_year_idx ON SUBSEQUENT_FILINGS1 USING btree (appln_filing_year);	
CREATE INDEX sec1_nb_prior_idx ON SUBSEQUENT_FILINGS1 USING btree (nb_priorities);
DROP TABLE t;



-- B.1 Information from equivalents (source = 2)
-- B.1.1 Find all the relevant information
DROP TABLE IF EXISTS EQUIVALENTS2;
CREATE TABLE EQUIVALENTS2 AS (
SELECT  t1.appln_id,  t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5,lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM SUBSEQUENT_FILINGS1 t1 
JOIN addresses_coordinates_all_inv t2 ON t1.subsequent_id = t2.appln_id
WHERE t1.nb_priorities = 1 AND lat IS NOT NULL );
DROP INDEX IF EXISTS equ2_idx, equ2_sub_idx, equ2_pers_idx, equ2_office_idx, equ2_year_idx;
CREATE INDEX equ2_idx ON EQUIVALENTS2 USING btree (appln_id);
CREATE INDEX equ2_sub_idx ON EQUIVALENTS2 USING btree (subsequent_id);
CREATE INDEX equ2_office_idx ON EQUIVALENTS2 USING btree (patent_office);
CREATE INDEX equ2_year_idx ON EQUIVALENTS2 USING btree (appln_filing_year);	

-- B.1.2 Select the most appropriate (i.e. earliest) equivalent
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2;
CREATE  TABLE EARLIEST_EQUIVALENT2 AS 
SELECT t1.appln_id, subsequent_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type, min
FROM EQUIVALENTS2 t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM EQUIVALENTS2
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS eequ_idx, eequ_sub_idx;
CREATE INDEX eequ2_idx ON EARLIEST_EQUIVALENT2 USING btree (appln_id);
CREATE INDEX eequ2_sub_idx ON EARLIEST_EQUIVALENT2 USING btree (subsequent_id);

-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2_;
CREATE TABLE EARLIEST_EQUIVALENT2_ AS
SELECT t1.* FROM earliest_equivalent2 t1 JOIN 
(SELECT appln_id, min(subsequent_id) 
FROM EARLIEST_EQUIVALENT2
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS eequ_idx_, eequ_sub_idx_;
CREATE INDEX eequ2_idx_ ON EARLIEST_EQUIVALENT2_ USING btree (appln_id);
CREATE INDEX eequ2_sub_idx_ ON EARLIEST_EQUIVALENT2_ USING btree (subsequent_id);

-- B.2 Information from other subsequent filings (source = 3)
-- B.2.1 Find information on inventors from subsequent filings for patents that have not yet been identified via their potential equivalent(s)
DROP TABLE IF EXISTS OTHER_SUBSEQUENT_FILINGS3;
CREATE TABLE OTHER_SUBSEQUENT_FILINGS3 AS (
SELECT t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM SUBSEQUENT_FILINGS1 t1 
JOIN addresses_coordinates_all_inv t2 ON t1.subsequent_id = t2.appln_id
WHERE t1.nb_priorities > 1 AND lat IS NOT NULL );
DROP INDEX IF EXISTS other3_idx, other3_sub_idx, other3_office_idy, other3_year_idx;
CREATE INDEX other3_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (appln_id);
CREATE INDEX other3_sub_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (subsequent_id);
CREATE INDEX other3_office_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (patent_office);
CREATE INDEX other3_year_idx ON OTHER_SUBSEQUENT_FILINGS3 USING btree (appln_filing_year);	

-- B.2.2 Select the most appropriate (i.e. earliest) subsequent filing
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3;
CREATE TABLE EARLIEST_SUBSEQUENT_FILING3 AS 
SELECT t1.appln_id, subsequent_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type, min
FROM OTHER_SUBSEQUENT_FILINGS3 t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM OTHER_SUBSEQUENT_FILINGS3
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS esub3_idx, esub3_sub_idx;
CREATE INDEX esub3_idx ON EARLIEST_SUBSEQUENT_FILING3 USING btree (appln_id);
CREATE INDEX esub3_sub_idx ON EARLIEST_SUBSEQUENT_FILING3 USING btree (subsequent_id);

-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3_;
CREATE TABLE EARLIEST_SUBSEQUENT_FILING3_ AS
SELECT t1.* FROM EARLIEST_SUBSEQUENT_FILING3 t1 JOIN 
(SELECT appln_id, min(subsequent_id) 
FROM EARLIEST_SUBSEQUENT_FILING3
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS esub3_idx_, esub3_sub_idx_;
CREATE INDEX esub3_idx_ ON EARLIEST_SUBSEQUENT_FILING3_ USING btree (appln_id);
CREATE INDEX esub3_sub_idx_ ON EARLIEST_SUBSEQUENT_FILING3_ USING btree (subsequent_id);

--Applicant information

-- C. Information that is directly available (source = 4)
--CREATE INDEX addresses_coordinates_all_app_lat ON addresses_coordinates_all_app (lat);
DROP TABLE IF EXISTS PRIORITY_FILINGS4;
CREATE TABLE PRIORITY_FILINGS4 AS (
SELECT DISTINCT t1.appln_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM PRIORITY_FILINGS_inv t1 
JOIN addresses_coordinates_all_app t2 ON t1.appln_id = t2.appln_id  WHERE t2.lat IS NOT NULL) ;
DROP INDEX IF EXISTS pri4_idx, pri4_office_idx, pri4_date_idx;
CREATE INDEX pri4_idx ON PRIORITY_FILINGS4 USING btree (appln_id);
CREATE INDEX pri4_office_idx ON PRIORITY_FILINGS4 USING btree (patent_office);
CREATE INDEX pri4_year_idx ON PRIORITY_FILINGS4 USING btree (appln_filing_year);

-- D.1 Use information from equivalents (source = 5)
-- D.1.1 Find all the relevant information
DROP TABLE IF EXISTS EQUIVALENTS5;
CREATE  TABLE EQUIVALENTS5 AS (
SELECT  t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM SUBSEQUENT_FILINGS1 t1 
JOIN addresses_coordinates_all_app t2 ON t1.subsequent_id = t2.appln_id
WHERE t1.nb_priorities = 1  AND lat IS NOT NULL);
DROP INDEX IF EXISTS equ5_idx, equ5_sub_idx, equ5_office_idx, equ5_year_idx;
CREATE INDEX equ5_idx ON EQUIVALENTS5 USING btree (appln_id);
CREATE INDEX equ5_sub_idx ON EQUIVALENTS5  USING btree (subsequent_id);
CREATE INDEX equ5_office_idx ON EQUIVALENTS5 USING btree (patent_office);
CREATE INDEX equ5_year_idx ON EQUIVALENTS5 USING btree (appln_filing_year);	

-- D.1.2 Select the most appropriate (i.e. earliest) equivalent
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT5;
CREATE  TABLE EARLIEST_EQUIVALENT5 AS 
SELECT t1.appln_id, subsequent_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type, min
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
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS eequ5_idx_,  eequ_sub_idx_;
CREATE INDEX eequ5_idx_ ON EARLIEST_EQUIVALENT5_ USING btree (appln_id);
CREATE INDEX eequ5_sub_idx_ ON EARLIEST_EQUIVALENT5_ USING btree (subsequent_id);

-- D.2 Use information from other subsequent filings (source = 6)
-- D.2.1 Find information on inventors from subsequent filings for patents that have not yet been identified via their potential equivalents
CREATE TEMP TABLE subsequent_filings1_nb_prior AS
SELECT * FROM subsequent_filings1 
WHERE nb_priorities > 1;
CREATE INDEX subsequent_filings1_nb_prior_idx ON subsequent_filings1_nb_prior(subsequent_id);
DROP TABLE IF EXISTS OTHER_SUBSEQUENT_FILINGS6;
CREATE TABLE OTHER_SUBSEQUENT_FILINGS6 AS (
SELECT  t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type
FROM subsequent_filings1_nb_prior t1 
JOIN addresses_coordinates_all_app t2 ON t1.subsequent_id = t2.appln_id
WHERE lat IS NOT NULL);
DROP TABLE subsequent_filings1_nb_prior;
DROP INDEX IF EXISTS other6_idx, other6_sub_idx, other6_office_idx, other6_year_idx;
CREATE INDEX other6_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (appln_id);
CREATE INDEX other6_sub_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (subsequent_id);
CREATE INDEX other6_office_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (patent_office);
CREATE INDEX other6_year_idx ON OTHER_SUBSEQUENT_FILINGS6 USING btree (appln_filing_year);	

-- D.2.2 Select the most appropriate (i.e. earliest) subsequent filing
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING6;
CREATE  TABLE EARLIEST_SUBSEQUENT_FILING6 AS 
SELECT t1.appln_id, subsequent_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, data_source, 
country_googlegeon, city_googlegeon, admin_level, sub_admin_level, subsub_admin_level, coord_source, type, min
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

-- table containing priority filings 
DROP TABLE IF EXISTS TABLE_INV;
CREATE TABLE table_inv AS
SELECT * from priority_filings_inv 
;

CREATE INDEX TABLE_INV_APPLN_ID ON TABLE_INV USING btree (appln_id);

DROP TABLE IF EXISTS TABLE_TO_BE_FILLED_INV;
CREATE  TABLE TABLE_TO_BE_FILLED_INV (
appln_id INTEGER DEFAULT NULL,
name_0 TEXT DEFAULT NULL,
name_1 TEXT DEFAULT NULL,
name_2 TEXT DEFAULT NULL,
name_3 TEXT DEFAULT NULL,
name_4 TEXT DEFAULT NULL,
name_5 TEXT DEFAULT NULL,
engtype_1 TEXT DEFAULT NULL,
engtype_2 TEXT DEFAULT NULL,
engtype_3 TEXT DEFAULT NULL,
engtype_4 TEXT DEFAULT NULL,
engtype_5 TEXT DEFAULT NULL,
lat REAL DEFAULT NULL,
lng REAL DEFAULT NULL,
lat_exact DECIMAL DEFAULT NULL,
lng_exact DECIMAL DEFAULT NULL,
geom GEOMETRY DEFAULT NULL,
geom_m GEOMETRY DEFAULT NULL,
viewportArea REAL DEFAULT NULL,
country_googlegeon VARCHAR DEFAULT NULL, 
city_googlegeon TEXT DEFAULT NULL, 
admin_level VARCHAR DEFAULT NULL, 
sub_admin_level VARCHAR DEFAULT NULL, 
subsub_admin_level VARCHAR DEFAULT NULL,
data_source VARCHAR DEFAULT NULL, 
coord_source TEXT DEFAULT NULL,
type TEXT DEFAULT NULL,
source INT DEFAULT NULL
); COMMENT ON TABLE TABLE_TO_BE_FILLED_INV IS 'Inventors from priority filings of a given (po, year)';


/* 
  MAIN PROCEDURE
*/


-- A Insert information that is directly available (source = 1)
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT t.appln_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, type, 1
FROM priority_filings1 t
WHERE lat IS NOT NULL;

CREATE INDEX TABLE_TO_BE_FILLED_INV_appln_id ON TABLE_TO_BE_FILLED_INV(appln_id);

-- delete information that has been added
DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);

-- B.1 Add the information from each selected equivalent
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.name_0,
t_.name_1,
t_.name_2,
t_.name_3,
t_.name_4,
t_.name_5,
t_.engtype_1,
t_.engtype_2,
t_.engtype_3,
t_.engtype_4,
t_.engtype_5,
t_.lat,
t_.lng,
t_.lat_exact,
t_.lng_exact,
t_.geom,
t_.geom_m,
t_.viewportArea,
t_.country_googlegeon,
t_.city_googlegeon,
t_.admin_level,
t_.sub_admin_level,
t_.subsub_admin_level,
t_.data_source,
t_.coord_source,
t_.type,
2 
FROM (
SELECT t1.appln_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, type
FROM EARLIEST_EQUIVALENT2_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE t1.lat IS NOT NULL 
) AS t_
;

DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);		 	      

-- B.2 Add the information from each selected subsequent filing
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.name_0,
t_.name_1,
t_.name_2,
t_.name_3,
t_.name_4,
t_.name_5,
t_.engtype_1,
t_.engtype_2,
t_.engtype_3,
t_.engtype_4,
t_.engtype_5,
t_.lat,
t_.lng,
t_.lat_exact,
t_.lng_exact,
t_.geom,
t_.geom_m,
t_.viewportArea,
t_.country_googlegeon,
t_.city_googlegeon,
t_.admin_level,
t_.sub_admin_level,
t_.subsub_admin_level,
t_.data_source,
t_.coord_source,
t_.type,
3 
FROM (
SELECT t1.appln_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, type
FROM EARLIEST_SUBSEQUENT_FILING3_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE t1.lat IS NOT NULL 
) AS t_
;

DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);	

-- Take information from applicants to recover missing information 

-- C Insert information that is directly available (source = 4)
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.name_0,
t_.name_1,
t_.name_2,
t_.name_3,
t_.name_4,
t_.name_5,
t_.engtype_1,
t_.engtype_2,
t_.engtype_3,
t_.engtype_4,
t_.engtype_5,
t_.lat,
t_.lng,
t_.lat_exact,
t_.lng_exact,
t_.geom,
t_.geom_m,
t_.viewportArea,
t_.country_googlegeon,
t_.city_googlegeon,
t_.admin_level,
t_.sub_admin_level,
t_.subsub_admin_level,
t_.data_source,
t_.coord_source,
t_.type,
4
FROM (
SELECT t1.appln_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, type
FROM PRIORITY_FILINGS4 t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE t1.lat IS NOT NULL 
) AS t_
;

DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);	

-- D.1 Add the information from each selected equivalent
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.name_0,
t_.name_1,
t_.name_2,
t_.name_3,
t_.name_4,
t_.name_5,
t_.engtype_1,
t_.engtype_2,
t_.engtype_3,
t_.engtype_4,
t_.engtype_5,
t_.lat,
t_.lng,
t_.lat_exact,
t_.lng_exact,
t_.geom,
t_.geom_m,
t_.viewportArea,
t_.country_googlegeon,
t_.city_googlegeon,
t_.admin_level,
t_.sub_admin_level,
t_.subsub_admin_level,
t_.data_source,
t_.coord_source,
t_.type,
5 
FROM (
SELECT t1.appln_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, type
FROM EARLIEST_EQUIVALENT5_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE t1.lat IS NOT NULL 
) AS t_
;

DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);	

-- D.2 Add the information from each selected subsequent filing
INSERT INTO TABLE_TO_BE_FILLED_INV
SELECT
t_.appln_id,
t_.name_0,
t_.name_1,
t_.name_2,
t_.name_3,
t_.name_4,
t_.name_5,
t_.engtype_1,
t_.engtype_2,
t_.engtype_3,
t_.engtype_4,
t_.engtype_5,
t_.lat,
t_.lng,
t_.lat_exact,
t_.lng_exact,
t_.geom,
t_.geom_m,
t_.viewportArea,
t_.country_googlegeon,
t_.city_googlegeon,
t_.admin_level,
t_.sub_admin_level,
t_.subsub_admin_level,
t_.data_source,
t_.coord_source,
t_.type,
6
FROM (
SELECT t1.appln_id, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, type
FROM EARLIEST_SUBSEQUENT_FILING6_ t1
JOIN (
SELECT DISTINCT appln_id FROM
TABLE_INV) AS t2
ON t1.appln_id = t2.appln_id 
WHERE t1.lat IS NOT NULL 
) AS t_
;

DELETE FROM TABLE_INV t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_TO_BE_FILLED_INV);	


-- Table with location information from all possible sources
DROP TABLE IF EXISTS PF_INV_GEOC;
CREATE TABLE PF_INV_GEOC (
appln_id INTEGER DEFAULT NULL,
--person_id INTEGER DEFAULT NULL,
patent_office CHAR(2) DEFAULT NULL,
priority_date date DEFAULT NULL,
priority_year INTEGER DEFAULT NULL,
name_0 TEXT DEFAULT NULL,
name_1 TEXT DEFAULT NULL,
name_2 TEXT DEFAULT NULL,
name_3 TEXT DEFAULT NULL,
name_4 TEXT DEFAULT NULL,
name_5 TEXT DEFAULT NULL,
engtype_1 TEXT DEFAULT NULL,
engtype_2 TEXT DEFAULT NULL,
engtype_3 TEXT DEFAULT NULL,
engtype_4 TEXT DEFAULT NULL,
engtype_5 TEXT DEFAULT NULL,
lat REAL DEFAULT NULL,
lng REAL DEFAULT NULL,
lat_exact DECIMAL DEFAULT NULL,
lng_exact DECIMAL DEFAULT NULL,
geom GEOMETRY DEFAULT NULL,
geom_m GEOMETRY DEFAULT NULL,
viewportArea REAL DEFAULT NULL,
country_googlegeon VARCHAR DEFAULT NULL, 
city_googlegeon TEXT DEFAULT NULL, 
admin_level VARCHAR DEFAULT NULL, 
sub_admin_level VARCHAR DEFAULT NULL, 
subsub_admin_level VARCHAR DEFAULT NULL,
data_source VARCHAR DEFAULT NULL, 
coord_source TEXT DEFAULT NULL,
source SMALLINT DEFAULT NULL,
type TEXT DEFAULT NULL
); COMMENT ON TABLE PF_INV_GEOC IS 'Inventors from priority filings of a given (po, year)';

-- E. Job done, insert into final table 
INSERT INTO PF_INV_GEOC
SELECT t1.appln_id, t2.patent_office, t2.appln_filing_date, t2.appln_filing_year, name_0, name_1, name_2, name_3, name_4, name_5, engtype_1, engtype_2, engtype_3, engtype_4, engtype_5, lat, lng, lat_exact, lng_exact, geom, geom_m, viewportArea, country_googlegeon, city_googlegeon, admin_level, 
sub_admin_level, subsub_admin_level, data_source, coord_source, source, type
FROM TABLE_TO_BE_FILLED_INV t1 
JOIN (SELECT DISTINCT appln_id, patent_office, appln_filing_date, appln_filing_year FROM PRIORITY_FILINGS_inv) AS t2 ON t1.appln_id = t2.appln_id;

CREATE INDEX PF_INV_GEOC_APPLN_ID ON PF_INV_GEOC(appln_id);
CREATE INDEX PF_INV_GEOC_YEAR ON PF_INV_GEOC(priority_year);



--   DROP TABLE if exists po;
--   DROP TABLE if exists toExclude;
--   DROP TABLE if exists PRIORITY_FILINGS_inv;
--   DROP TABLE if exists TABLE_TO_BE_FILLED_INV;
--   DROP TABLE if exists TABLE_INV;
--   DROP table if exists addresses_coordinates_all_app;
--   DROP table if exists addresses_coordinates_all_inv;
--   DROP table if exists PRIORITY_FILINGS1;
--   DROP table if exists SUBSEQUENT_FILINGS1;
--   DROP table if exists EQUIVALENTS2;
--   DROP table if exists EARLIEST_EQUIVALENT2;
--   DROP table if exists EARLIEST_EQUIVALENT2_;
--   DROP table if exists OTHER_SUBSEQUENT_FILINGS3;
--   DROP table if exists EARLIEST_SUBSEQUENT_FILING3;
--   DROP table if exists EARLIEST_SUBSEQUENT_FILING3_;
--   DROP table if exists PRIORITY_FILINGS4;
--   DROP table if exists EQUIVALENTS5;
--   DROP table if exists EARLIEST_EQUIVALENT5;
--   DROP table if exists EARLIEST_EQUIVALENT5_;
--   DROP table if exists OTHER_SUBSEQUENT_FILINGS6;
--   DROP table if exists EARLIEST_SUBSEQUENT_FILING6;
--   DROP table if exists EARLIEST_SUBSEQUENT_FILING6_;


