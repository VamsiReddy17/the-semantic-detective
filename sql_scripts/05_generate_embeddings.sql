-- =================================================================================
-- 05_generate_embeddings.sql - Generate Embeddings for All Support Tickets
-- =================================================================================
-- Purpose: Create vector embeddings for all support tickets to enable semantic search
--          This is a one-time batch process that embeds ~8.6K tickets
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- Source Table: insightweaver.hackathon_ai.support_tickets_master
-- Target Table: insightweaver.hackathon_ai.support_tickets_with_embeddings
-- Model: insightweaver.hackathon_ai.text_embedding_model
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- 
-- Prerequisites:
-- 1. AI models created (04_models.sql)
-- 2. Clean data tables created (02_clean_data.sql)
-- 3. BigQuery dataset: insightweaver.hackathon_ai
-- 
-- UPDATED: Now includes ALL columns from master table:
-- - status: For precise filtering (closed/open/pending)
-- - customer_age: For demographic analysis
-- - customer_gender: For demographic analysis
-- - first_response_time: For performance analytics
-- - time_to_resolution: For SLA monitoring
-- =================================================================================

-- =================================================================================
-- STEP 1: Generate Embeddings for All Tickets
-- =================================================================================
-- This creates a comprehensive embeddings table with:
-- - All original ticket data
-- - Combined text optimized for embedding
-- - 768-dimensional embedding vectors
-- - Metadata for tracking and debugging

CREATE OR REPLACE TABLE `insightweaver.hackathon_ai.support_tickets_with_embeddings` AS
SELECT
  -- Original ticket information (ALL COLUMNS from master table)
  ticket_id,
  customer_name,
  customer_email,
  customer_age,           -- ✅ For demographic analysis
  customer_gender,        -- ✅ For demographic analysis  
  product_purchased,
  date_of_purchase,
  ticket_type,
  subject,
  description,
  status,                 -- ✅ For precise filtering (closed/open/pending)
  resolution,
  priority,
  channel,
  first_response_time,    -- ✅ For performance analytics
  time_to_resolution,     -- ✅ For SLA monitoring
  cust_satisfaction,

  -- =================================================================================
  -- OPTIMIZED TEXT FOR EMBEDDING
  -- =================================================================================
  -- This field combines the most important information for semantic search:
  -- - Subject: Brief issue description
  -- - Description: Detailed problem (with product placeholders resolved)
  -- - Resolution: How it was solved (if available)
  -- 
  -- Format: "Subject: [subject]\nDescription: [description]\nResolution: [resolution]"
  -- This structure helps the embedding model understand context and relationships
  CONCAT(
    'Subject: ', COALESCE(subject, ''), '\n',
    'Description: ', COALESCE(description, ''), '\n',
    'Resolution: ', COALESCE(resolution, '')
  ) AS text_for_embedding,

  -- =================================================================================
  -- EMBEDDING VECTOR GENERATION
  -- =================================================================================
  -- Generate 768-dimensional embedding using text-embedding-005
  -- This vector represents the semantic meaning of the ticket content
  ml_generate_embedding_result AS embedding,

  -- =================================================================================
  -- METADATA FOR TRACKING AND DEBUGGING
  -- =================================================================================
  'text-embedding-005' AS embedding_model,
  CURRENT_TIMESTAMP() AS embedded_at,
  LENGTH(CONCAT(
    'Subject: ', COALESCE(subject, ''), '\n',
    'Description: ', COALESCE(description, ''), '\n',
    'Resolution: ', COALESCE(resolution, '')
  )) AS text_length

FROM ML.GENERATE_EMBEDDING(
  MODEL `insightweaver.hackathon_ai.text_embedding_model`,
  (
    SELECT
      -- All columns from master table (including new ones)
      ticket_id,
      customer_name,
      customer_email,
      customer_age,           -- ✅ For demographic analysis
      customer_gender,        -- ✅ For demographic analysis
      product_purchased,
      date_of_purchase,
      ticket_type,
      subject,
      description,
      status,                 -- ✅ For precise filtering
      resolution,
      priority,
      channel,
      first_response_time,    -- ✅ For performance analytics
      time_to_resolution,     -- ✅ For SLA monitoring
      cust_satisfaction,
      
      -- Text content for embedding (same as text_for_embedding field)
      CONCAT(
        'Subject: ', COALESCE(subject, ''), '\n',
        'Description: ', COALESCE(description, ''), '\n',
        'Resolution: ', COALESCE(resolution, '')
      ) AS content
    FROM `insightweaver.hackathon_ai.support_tickets_master`
  )
);

-- =================================================================================
-- STEP 2: Validate Embedding Generation
-- =================================================================================

-- Check embedding generation results
SELECT 
  'Embedding Generation Summary' as metric,
  COUNT(*) as total_tickets,
  COUNT(embedding) as tickets_with_embeddings,
  COUNT(*) - COUNT(embedding) as tickets_without_embeddings,
  MIN(embedded_at) as first_embedding_time,
  MAX(embedded_at) as last_embedding_time
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`;

-- Verify embedding dimensions (should be 768 for text-embedding-005)
SELECT 
  'Embedding Dimensions Check' as check_type,
  ARRAY_LENGTH(embedding) as embedding_dimensions,
  COUNT(*) as ticket_count
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE embedding IS NOT NULL
GROUP BY ARRAY_LENGTH(embedding)
ORDER BY embedding_dimensions;

-- Check text length distribution
SELECT 
  'Text Length Distribution' as metric,
  MIN(text_length) as min_length,
  MAX(text_length) as max_length,
  AVG(text_length) as avg_length,
  APPROX_QUANTILES(text_length, 100)[OFFSET(50)] as median_length,
  APPROX_QUANTILES(text_length, 100)[OFFSET(95)] as p95_length
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE embedding IS NOT NULL;

-- Sample of generated embeddings for verification
SELECT 
  ticket_id,
  subject,
  LEFT(text_for_embedding, 100) as text_preview,
  ARRAY_LENGTH(embedding) as embedding_dimensions,
  embedding[OFFSET(0)] as first_dimension,
  embedding[OFFSET(1)] as second_dimension,
  embedded_at
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE embedding IS NOT NULL
ORDER BY ticket_id
LIMIT 5;

-- =================================================================================
-- STEP 3: Data Quality Checks
-- =================================================================================

-- Check for any failed embeddings
SELECT 
  'Failed Embeddings' as issue_type,
  ticket_id,
  subject,
  text_length,
  embedded_at
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE embedding IS NULL
ORDER BY ticket_id;

-- Check for extremely long text that might cause issues
SELECT 
  'Long Text Check' as check_type,
  ticket_id,
  subject,
  text_length,
  LEFT(text_for_embedding, 200) as text_preview
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE text_length > 5000  -- Adjust threshold as needed
ORDER BY text_length DESC
LIMIT 10;

-- =================================================================================
-- STEP 4: Performance and Cost Analysis
-- =================================================================================

-- Estimate processing time and cost
SELECT 
  'Processing Summary' as summary_type,
  COUNT(*) as total_tickets_processed,
  SUM(text_length) as total_characters_processed,
  AVG(text_length) as avg_characters_per_ticket,
  -- Rough cost estimate (text-embedding-005: ~$0.0001 per 1K tokens)
  -- Assuming ~4 characters per token
  ROUND(SUM(text_length) / 4000 * 0.0001, 4) as estimated_cost_usd
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE embedding IS NOT NULL;

-- =================================================================================
-- STEP 3: Verify New Columns
-- =================================================================================

-- Check that all new columns are present and populated
SELECT 
  'New Columns Verification' as check_type,
  COUNT(*) as total_tickets,
  COUNT(status) as with_status,
  COUNT(customer_age) as with_customer_age,
  COUNT(customer_gender) as with_customer_gender,
  COUNT(first_response_time) as with_first_response_time,
  COUNT(time_to_resolution) as with_time_to_resolution
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`;

-- Check status distribution
SELECT 
  'Status Distribution' as check_type,
  status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
GROUP BY status
ORDER BY count DESC;

-- Sample data with new columns
SELECT 
  'Sample Data with New Columns' as check_type,
  ticket_id,
  subject,
  status,
  customer_age,
  customer_gender,
  priority,
  cust_satisfaction,
  ARRAY_LENGTH(embedding) as embedding_size
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
WHERE embedding IS NOT NULL
LIMIT 5;

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- Common issues and solutions:
-- 
-- 1. "Embedding generation failed" for some tickets
--    → Check for NULL or empty text content
--    → Verify text length is within limits (~8K tokens)
--    → Ensure text doesn't contain invalid characters
-- 
-- 2. "Inconsistent embedding dimensions"
--    → All embeddings should be 768 dimensions for text-embedding-005
--    → If dimensions vary, there may be model endpoint issues
--    → Re-run embedding generation for affected tickets
-- 
-- 3. "Long processing time"
--    → This is normal for ~8.6K tickets
--    → Processing typically takes 5-15 minutes
--    → Monitor BigQuery job progress in the console
-- 
-- 4. "High cost"
--    → Monitor token usage in Cloud Console
--    → Consider truncating very long descriptions if needed
--    → Set up billing alerts for cost control
-- 
-- 5. "Memory or quota errors"
--    → Check BigQuery slot availability
--    → Verify Vertex AI quota limits
--    → Consider processing in smaller batches if needed
-- 
-- =================================================================================
-- NEXT STEPS
-- =================================================================================
-- 
-- After successful embedding generation:
-- 1. Create vector index for scalable search (06_vector_index.sql)
-- 2. Test semantic search functionality (07_semantic_search.sql)
-- 3. Implement RAG response generation (08_gemini_rag.sql)
-- 
-- =================================================================================
