-- =================================================================================
-- 04_models.sql - Create AI Model References for Embedding and Text Generation
-- =================================================================================
-- Purpose: Create remote model references to Google's Vertex AI models
--          for embedding generation and text generation (RAG)
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- Connection: insightweaver.us.hackathon_ai_connection
-- Models: insightweaver.hackathon_ai.text_embedding_model
--         insightweaver.hackathon_ai.text_gen_model
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- - hackathon_ai_connection → YOUR_CONNECTION_NAME
-- 
-- Prerequisites:
-- 1. BigQuery ↔ Vertex AI connection created (see 03_connection_setup.md)
-- 2. IAM roles granted to connection service account
-- 3. BigQuery dataset: insightweaver.hackathon_ai
-- =================================================================================

-- =================================================================================
-- STEP 1: Create Text Embedding Model Reference
-- =================================================================================
-- Model: text-embedding-005
-- Purpose: Generate vector embeddings for semantic similarity search
-- Input: Text content (up to ~8K tokens)
-- Output: 768-dimensional embedding vector

CREATE OR REPLACE MODEL `insightweaver.hackathon_ai.text_embedding_model`
REMOTE WITH CONNECTION `insightweaver.us.hackathon_ai_connection`
OPTIONS (
  ENDPOINT = 'text-embedding-005'
);

-- =================================================================================
-- STEP 2: Create Text Generation Model Reference
-- =================================================================================
-- Model: gemini-2.5-flash
-- Purpose: Generate contextual responses using retrieved similar tickets (RAG)
-- Input: Prompt with context from similar tickets
-- Output: Generated text response

CREATE OR REPLACE MODEL `insightweaver.hackathon_ai.text_gen_model`
REMOTE WITH CONNECTION `insightweaver.us.hackathon_ai_connection`
OPTIONS (
  ENDPOINT = 'gemini-2.5-flash'
);

-- =================================================================================
-- STEP 3: Test Model Creation and Basic Functionality
-- =================================================================================

-- Test embedding model with a sample text
-- This verifies the connection and model are working correctly
SELECT 
  'Embedding Model Test' as test_type,
  ARRAY_LENGTH(ml_generate_embedding_result) as embedding_dimensions,
  ml_generate_embedding_result[OFFSET(0)] as first_dimension_sample
FROM ML.GENERATE_EMBEDDING(
  MODEL `insightweaver.hackathon_ai.text_embedding_model`,
  (SELECT 'Test embedding generation for support ticket search' AS content)
);

-- Test text generation model with a simple prompt
-- This verifies the Gemini model is accessible
SELECT 
  'Text Generation Model Test' as test_type,
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS generated_text
FROM ML.GENERATE_TEXT(
  MODEL `insightweaver.hackathon_ai.text_gen_model`,
  (SELECT 'Generate a brief response to a customer support ticket about login issues.' AS prompt)
);

-- =================================================================================
-- STEP 4: Model Information and Metadata
-- =================================================================================

-- Get information about the created models
SELECT 
  model_name,
  model_type,
  creation_time,
  last_modified_time
FROM `insightweaver.hackathon_ai.INFORMATION_SCHEMA.MODELS`
WHERE model_name IN ('text_embedding_model', 'text_gen_model')
ORDER BY creation_time;

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- Common issues and solutions:
-- 
-- 1. "Connection not found" error
--    → Verify the connection exists: bq ls --connection --location=US
--    → Check connection string format: project.region.connection
--    → Ensure connection was created in the same region (US)
-- 
-- 2. "Permission denied" error
--    → Verify IAM roles are granted to the connection service account:
--      - roles/aiplatform.user
--      - roles/bigquery.jobUser
--    → Check service account ID matches exactly
-- 
-- 3. "Invalid endpoint" error
--    → Verify endpoint names are correct:
--      - text-embedding-005 (for embeddings)
--      - gemini-2.5-flash (for text generation)
--    → Check Vertex AI API is enabled in your project
-- 
-- 4. "Model creation timeout"
--    → Model creation is usually fast (< 30 seconds)
--    → If it times out, check network connectivity
--    → Verify Vertex AI quota limits are not exceeded
-- 
-- 5. "Test queries fail"
--    → Run the test queries above to verify models work
--    → Check that the connection service account has proper permissions
--    → Ensure Vertex AI models are available in your region
-- 
-- =================================================================================
-- MODEL SPECIFICATIONS
-- =================================================================================
-- 
-- text-embedding-005:
-- - Input: Text content (up to ~8,192 tokens)
-- - Output: 768-dimensional float array
-- - Use case: Semantic similarity, clustering, classification
-- - Cost: ~$0.0001 per 1K tokens
-- 
-- gemini-2.5-flash:
-- - Input: Text prompt (up to ~1M tokens)
-- - Output: Generated text response
-- - Use case: Text generation, summarization, Q&A
-- - Cost: ~$0.075 per 1M input tokens, ~$0.30 per 1M output tokens
-- 
-- =================================================================================
