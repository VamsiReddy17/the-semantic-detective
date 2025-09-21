-- =================================================================================
-- 01_load_data.sql - Load Customer Support Ticket Data from GCS to BigQuery
-- =================================================================================
-- Purpose: Load the customer support ticket CSV from Google Cloud Storage
--          into a BigQuery table for further processing
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- GCS Bucket: insightweaver_storage
-- Connection: insightweaver.us.hackathon_ai_connection
-- 
-- DATA SOURCE:
-- Kaggle Dataset: "suraj520/customer-support-ticket-dataset"
-- Local File: Data/TicketData_customer_support_tickets.csv
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- - insightweaver_storage → YOUR_BUCKET_NAME
-- 
-- Prerequisites:
-- 1. CSV file uploaded to GCS (see STEP 1 below)
-- 2. BigQuery dataset created: insightweaver.hackathon_ai
-- 3. BigQuery job user permissions
-- 4. gcloud CLI installed and authenticated
-- =================================================================================

-- =================================================================================
-- STEP 1: Upload Local CSV File to Google Cloud Storage
-- =================================================================================
-- Before running the BigQuery commands below, you need to upload your local CSV file
-- to Google Cloud Storage. Follow these steps:

-- 1.1: Create a GCS bucket (if it doesn't exist)
-- Run this command in Cloud Shell or your local terminal:
-- gsutil mb gs://insightweaver_storage

-- 1.2: Create the TicketData folder in your bucket
-- gsutil mkdir gs://insightweaver_storage/TicketData

-- 1.3: Upload your local CSV file to GCS
-- gsutil cp "Data/TicketData_customer_support_tickets.csv" gs://insightweaver_storage/TicketData/

-- 1.4: Verify the upload
-- gsutil ls gs://insightweaver_storage/TicketData/

-- Expected output should show:
-- gs://insightweaver_storage/TicketData/customer_support_tickets.csv

-- 1.5: Check file size and details
-- gsutil ls -l gs://insightweaver_storage/TicketData/customer_support_tickets.csv

-- This should show the file size (should be several MB for ~8.6K tickets)

-- =================================================================================
-- STEP 2: Load Data from GCS to BigQuery
-- =================================================================================

-- Create dataset (only run once)
CREATE SCHEMA IF NOT EXISTS `insightweaver.hackathon_ai`
OPTIONS (
  description = "Dataset for Semantic Detective - Support Ticket Search with BigQuery AI",
  location = "US"
);

-- Load CSV data from Google Cloud Storage into BigQuery
-- Note: This creates a raw table with all columns as STRING type initially
CREATE OR REPLACE EXTERNAL TABLE `insightweaver.hackathon_ai.support_tickets_raw_csv`
OPTIONS (
  format = 'CSV',
  uris = ['gs://insightweaver_storage/TicketData/customer_support_tickets.csv'],
  skip_leading_rows = 1,  -- Skip header row
  allow_quoted_newlines = true,  -- Handle multi-line descriptions
  allow_jagged_rows = true,  -- Handle rows with varying column counts
  field_delimiter = ',',
  quote = '"',
  escape = '"'
);

-- Verify the data was loaded correctly
-- Run this query to check the first few rows and schema
SELECT 
  *
FROM `insightweaver.hackathon_ai.support_tickets_raw_csv`
LIMIT 5;

-- Check total row count
SELECT 
  COUNT(*) as total_tickets
FROM `insightweaver.hackathon_ai.support_tickets_raw_csv`;

-- Check for any data quality issues
SELECT 
  COUNT(*) as total_rows,
  COUNT(DISTINCT `Ticket ID`) as unique_ticket_ids,
  COUNT(DISTINCT `Customer Email`) as unique_customers
FROM `insightweaver.hackathon_ai.support_tickets_raw_csv`;

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- If you encounter errors:
-- 
-- 1. "Bucket not found" or "Access denied" during upload
--    → Ensure you have Storage Admin or Storage Object Admin role
--    → Check that your project ID is correct: gcloud config get-value project
--    → Verify the bucket name is unique (GCS bucket names must be globally unique)
-- 
-- 2. "File not found" during upload
--    → Check that you're in the correct directory (project root)
--    → Verify the file path: Data/TicketData_customer_support_tickets.csv
--    → Use absolute path if needed: gsutil cp "/full/path/to/Data/TicketData_customer_support_tickets.csv" gs://insightweaver_storage/TicketData/
-- 
-- 3. "Access Denied" or "Permission denied" in BigQuery
--    → Ensure your service account has BigQuery Data Editor role
--    → Verify the GCS bucket is accessible from BigQuery
--    → Check that the file is uploaded and accessible: gsutil ls gs://insightweaver_storage/TicketData/
-- 
-- 4. "Invalid URI" or "File not found" in BigQuery
--    → Double-check the GCS path: gs://insightweaver_storage/TicketData/customer_support_tickets.csv
--    → Ensure the file exists and is publicly readable or your service account has access
--    → Verify the upload completed successfully
-- 
-- 5. "CSV parsing errors"
--    → The CSV contains multi-line descriptions, so allow_quoted_newlines = true is essential
--    → Some rows may have varying column counts, hence allow_jagged_rows = true
-- 
-- 6. "Schema mismatch"
--    → All columns are initially loaded as STRING type
--    → Data type conversion happens in the next step (02_clean_data.sql)
-- 
-- =================================================================================
