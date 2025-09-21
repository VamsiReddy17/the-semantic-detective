-- =================================================================================
-- 02_clean_data.sql - Data Cleaning and Schema Normalization
-- =================================================================================
-- Purpose: Convert raw CSV data into clean, normalized tables with proper data types
--          and create enriched text fields for embedding generation
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- Source Table: insightweaver.hackathon_ai.support_tickets_raw_csv
-- Target Tables: insightweaver.hackathon_ai.support_tickets_raw
--                insightweaver.hackathon_ai.support_tickets_master
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- 
-- Prerequisites:
-- 1. support_tickets_raw_csv table created (from 01_load_data.sql)
-- 2. BigQuery dataset: insightweaver.hackathon_ai
-- =================================================================================

-- =================================================================================
-- STEP 1: Create canonical raw table with clean schema and proper data types
-- =================================================================================

CREATE OR REPLACE TABLE `insightweaver.hackathon_ai.support_tickets_raw` AS
SELECT
  -- Primary identifiers
  `Ticket ID` AS ticket_id,
  `Customer Name` AS customer_name,
  `Customer Email` AS customer_email,
  
  -- Customer demographics (with safe casting)
  SAFE_CAST(`Customer Age` AS INT64) AS customer_age,
  `Customer Gender` AS customer_gender,
  
  -- Product information
  `Product Purchased` AS product_purchased,
  
  -- Date handling - convert to TIMESTAMP for consistency
  CAST(`Date of Purchase` AS TIMESTAMP) AS date_of_purchase,
  
  -- Ticket details
  `Ticket Type` AS ticket_type,
  `Ticket Subject` AS subject,
  `Ticket Description` AS description,
  `Ticket Status` AS status,
  `Resolution` AS resolution,
  `Ticket Priority` AS priority,
  `Ticket Channel` AS channel,
  
  -- Time metrics
  `First Response Time` AS first_response_time,
  `Time to Resolution` AS time_to_resolution,
  
  -- Customer satisfaction (with safe casting)
  SAFE_CAST(`Customer Satisfaction Rating` AS FLOAT64) AS cust_satisfaction

FROM `insightweaver.hackathon_ai.support_tickets_raw_csv`;

-- =================================================================================
-- STEP 2: Create enriched master table for semantic embeddings
-- =================================================================================
-- This table includes:
-- - Normalized categorical fields (lowercase)
-- - Product placeholder replacement in descriptions
-- - Combined text field optimized for embedding generation

CREATE OR REPLACE TABLE `insightweaver.hackathon_ai.support_tickets_master` AS
SELECT
  -- Core ticket information
  ticket_id,
  customer_name,
  customer_email,
  customer_age,
  
  -- Normalized categorical fields (lowercase for consistency)
  LOWER(customer_gender) AS customer_gender,
  product_purchased,
  date_of_purchase,
  LOWER(ticket_type) AS ticket_type,
  subject,
  
  -- Clean description with product placeholder replacement
  -- Replace {product_purchased} placeholder with actual product name
  REPLACE(description, '{product_purchased}', product_purchased) AS description,
  
  -- Normalized status and priority
  LOWER(status) AS status,
  resolution,
  LOWER(priority) AS priority,
  LOWER(channel) AS channel,
  
  -- Time metrics
  first_response_time,
  time_to_resolution,
  cust_satisfaction,

  -- =================================================================================
  -- CRITICAL: Create enriched text field for embedding generation
  -- =================================================================================
  -- This field combines the most important text content for semantic search:
  -- - Subject: Brief description of the issue
  -- - Description: Detailed problem description (with product placeholders resolved)
  -- - Resolution: How the issue was resolved (if available)
  --
  -- Format: "Subject: [subject]. Description: [description]. Resolution: [resolution]"
  -- This structure helps the embedding model understand the full context
  CONCAT(
    'Subject: ', COALESCE(subject, ''), '. ',
    'Description: ', COALESCE(REPLACE(description, '{product_purchased}', product_purchased), ''), '. ',
    'Resolution: ', COALESCE(resolution, '')
  ) AS text_for_embedding

FROM `insightweaver.hackathon_ai.support_tickets_raw`;

-- =================================================================================
-- STEP 3: Data Quality Validation and Statistics
-- =================================================================================

-- Check data quality and completeness
SELECT 
  'Data Quality Summary' as metric,
  COUNT(*) as total_tickets,
  COUNT(DISTINCT ticket_id) as unique_tickets,
  COUNT(DISTINCT customer_email) as unique_customers,
  COUNT(DISTINCT product_purchased) as unique_products,
  COUNT(DISTINCT ticket_type) as unique_ticket_types,
  COUNT(DISTINCT status) as unique_statuses
FROM `insightweaver.hackathon_ai.support_tickets_master`;

-- Check for missing values in critical fields
SELECT 
  'Missing Values Check' as check_type,
  COUNT(*) - COUNT(ticket_id) as missing_ticket_ids,
  COUNT(*) - COUNT(subject) as missing_subjects,
  COUNT(*) - COUNT(description) as missing_descriptions,
  COUNT(*) - COUNT(text_for_embedding) as missing_embedding_text
FROM `insightweaver.hackathon_ai.support_tickets_master`;

-- Sample of cleaned data for verification
SELECT 
  ticket_id,
  subject,
  LEFT(description, 100) as description_preview,
  LEFT(text_for_embedding, 150) as embedding_text_preview,
  status,
  priority,
  cust_satisfaction
FROM `insightweaver.hackathon_ai.support_tickets_master`
ORDER BY ticket_id
LIMIT 5;

-- Check text length distribution for embedding optimization
SELECT 
  'Text Length Distribution' as metric,
  MIN(LENGTH(text_for_embedding)) as min_length,
  MAX(LENGTH(text_for_embedding)) as max_length,
  AVG(LENGTH(text_for_embedding)) as avg_length,
  APPROX_QUANTILES(LENGTH(text_for_embedding), 100)[OFFSET(50)] as median_length,
  APPROX_QUANTILES(LENGTH(text_for_embedding), 100)[OFFSET(95)] as p95_length
FROM `insightweaver.hackathon_ai.support_tickets_master`
WHERE text_for_embedding IS NOT NULL;

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- Common issues and solutions:
-- 
-- 1. "Invalid date format" errors
--    → The original CSV uses YYYY-MM-DD format which BigQuery handles well
--    → If you see date parsing errors, check the actual format in your CSV
-- 
-- 2. "Product placeholder not replaced"
--    → Verify that {product_purchased} appears in the original descriptions
--    → Check that product_purchased field is not NULL
-- 
-- 3. "Text too long for embedding"
--    → text-embedding-005 can handle up to ~8K tokens
--    → If text_for_embedding is too long, consider truncating or summarizing
-- 
-- 4. "Missing embedding text"
--    → Ensure all critical fields (subject, description) are not NULL
--    → The COALESCE function handles NULL values gracefully
-- 
-- =================================================================================
