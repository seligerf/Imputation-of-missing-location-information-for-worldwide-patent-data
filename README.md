# Imputation-of-missing-location-information-for-worldwide-patent-data

We provide three pieces of SQL code:

1) imputation_of_location_information.sql: Algorithm to impute missing geographic information of first patent filings by inventors from subsequent filings (geocoded patent address information from multiple patent offices).

2) imputation_priority_filings_inv_ctry_codes.sql and imputation_priority_filings_app_ctry_codes: Algorithm to impute missing country codes of first patent filings by inventors from subsequent filings. It updates the code provided by de Rassenfosse, G., Dernis, H., Guellec, D., Picci, L., van Pottelsberghe de la Potterie, B., 2013: The worldwide count of priority patents: A new indicator of inventive activity. Research Policy. It can be directly run with PATSTAT Spring 2020.

3) first_and_subsequent_filings_and_patent_numbers.sql: Builds table in order to assign any patent number to its "first patent filing". It can be run with PATSTAT Spring 2020.

A detailed data description can be found in
de Rassenfosse, Kozak, Seliger 2019: Geocoding of worldwide patent data, Scientific Data, 6, available at https://www.nature.com/articles/s41597-019-0264-6
Please make sure to cite the paper in your work.
  
