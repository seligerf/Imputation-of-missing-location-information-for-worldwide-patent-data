# Imputation-of-missing-location-information-for-worldwide-patent-data

We provide three pieces of SQL code:

1) imputation_of_location_information.sql: Algorithm to impute missing geographic information of first patent filings by inventors from subsequent filings for use with geocoded patent address information from multiple patent offices together with PATSTAT.

2) imputation_of_PATSTAT_country_codes.sql: Algorithm to impute missing country codes of first patent filings by inventors from subsequent filings. It updates the code provided by de Rassenfosse, G., Dernis, H., Guellec, D., Picci, L., van Pottelsberghe de la Potterie, B., 2013: The worldwide count of priority patents: A new indicator of inventive activity. Research Policy. It can be directly run with PATSTAT Spring 2019.

3) first_and_subsequent_filings.sql: Buils table in order to assign any patent number to its "first patent filing". It can be run with PATSTAT Spring 2019.
  
