-- =================================================================================
-- 06_vector_index.sql - Create Vector Index for Scalable Similarity Search
-- =================================================================================
-- Purpose: Create an IVF (Inverted File) vector index to enable fast approximate
--          nearest neighbor search over the embedding vectors
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- Source Table: insightweaver.hackathon_ai.support_tickets_with_embeddings
-- Index: insightweaver.hackathon_ai.ticket_embedding_index
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- 
-- Prerequisites:
-- 1. Embeddings table created (05_generate_embeddings.sql)
-- 2. BigQuery dataset: insightweaver.hackathon_ai
-- 3. Sufficient BigQuery storage quota
-- =================================================================================

-- =================================================================================
-- STEP 1: Create IVF Vector Index
-- =================================================================================
-- IVF (Inverted File) index provides:
-- - Fast approximate nearest neighbor search
-- - Scalable to millions of vectors
-- - Cosine similarity distance metric
-- - Automatic index maintenance

CREATE OR REPLACE VECTOR INDEX `insightweaver.hackathon_ai.ticket_embedding_index`
ON `insightweaver.hackathon_ai.support_tickets_with_embeddings` (embedding)
OPTIONS(
  index_type = 'IVF',           -- Inverted File index for scalability
  distance_type = 'COSINE'      -- Cosine similarity for semantic search
);

-- =================================================================================
-- STEP 2: Monitor Index Creation Progress
-- =================================================================================
-- Note: Index creation is asynchronous and may take several minutes
-- Monitor progress in BigQuery console or using the query below

-- Check index creation status
SELECT 
  index_name,
  table_name,
  index_type,
  distance_type,
  creation_time,
  last_modified_time,
  index_status
FROM `insightweaver.hackathon_ai.INFORMATION_SCHEMA.VECTOR_INDEXES`
WHERE index_name = 'ticket_embedding_index';

-- =================================================================================
-- STEP 3: Validate Index Creation
-- =================================================================================

-- Wait for index to be built, then verify it's ready
-- This query will show the index status
SELECT 
  'Index Status Check' as check_type,
  CASE 
    WHEN index_status = 'ACTIVE' THEN 'Index is ready for use'
    WHEN index_status = 'BUILDING' THEN 'Index is being built - please wait'
    WHEN index_status = 'FAILED' THEN 'Index creation failed - check logs'
    ELSE 'Unknown status: ' || index_status
  END as status_message,
  creation_time,
  last_modified_time
FROM `insightweaver.hackathon_ai.INFORMATION_SCHEMA.VECTOR_INDEXES`
WHERE index_name = 'ticket_embedding_index';

-- =================================================================================
-- STEP 4: Test Vector Index with VECTOR_SEARCH
-- =================================================================================
-- Once the index is ACTIVE, test it with a sample query

-- Test vector search using the index
-- This query finds the 5 most similar tickets to a sample query
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. Invalid credentials.' AS content)
          ) AS e
         ) AS query_vector
)
SELECT 
  s.ticket_id,
  s.subject,
  s.text_for_embedding,
  distance
FROM VECTOR_SEARCH(
  TABLE `insightweaver.hackathon_ai.support_tickets_with_embeddings`,
  'embedding',
  (SELECT query_vector FROM query_embedding),
  top_k => 5,
  distance_type => 'COSINE'
) AS s
ORDER BY distance ASC;  -- Lower distance = higher similarity

-- =================================================================================
-- STEP 5: Performance Comparison
-- =================================================================================
-- Compare performance between manual cosine similarity and vector index search

-- Manual cosine similarity (from 07_semantic_search.sql)
-- This is slower but more precise for small datasets
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. Invalid credentials.' AS content)
          ) AS e
         ) AS qvec
)
SELECT 
  'Manual Cosine Similarity' as method,
  s.ticket_id,
  s.subject,
  SAFE_DIVIDE(
    (SELECT SUM(qv * sv)
     FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
     JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)),
    (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
     SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y)))
  ) AS cosine_similarity
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
CROSS JOIN query_embedding q
WHERE s.embedding IS NOT NULL
ORDER BY cosine_similarity DESC
LIMIT 5;

-- Vector index search (faster for large datasets)
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. Invalid credentials.' AS content)
          ) AS e
         ) AS query_vector
)
SELECT 
  'Vector Index Search' as method,
  s.ticket_id,
  s.subject,
  1 - distance AS cosine_similarity  -- Convert distance to similarity
FROM VECTOR_SEARCH(
  TABLE `insightweaver.hackathon_ai.support_tickets_with_embeddings`,
  'embedding',
  (SELECT query_vector FROM query_embedding),
  top_k => 5,
  distance_type => 'COSINE'
) AS s
ORDER BY distance ASC;

-- =================================================================================
-- STEP 6: Index Maintenance and Monitoring
-- =================================================================================

-- Check index size and storage usage
SELECT 
  'Index Storage Info' as info_type,
  table_name,
  index_name,
  index_type,
  -- Note: Exact storage size may not be available in INFORMATION_SCHEMA
  -- Monitor through BigQuery console for detailed storage metrics
  creation_time,
  last_modified_time
FROM `insightweaver.hackathon_ai.INFORMATION_SCHEMA.VECTOR_INDEXES`
WHERE index_name = 'ticket_embedding_index';

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- Common issues and solutions:
-- 
-- 1. "Index creation failed"
--    → Check that embeddings table exists and has data
--    → Verify all embeddings have consistent dimensions (768)
--    → Ensure sufficient BigQuery storage quota
--    → Check for any NULL embeddings that might cause issues
-- 
-- 2. "Index status stuck at BUILDING"
--    → Index creation can take 10-30 minutes for large datasets
--    → Monitor progress in BigQuery console
--    → Check for any concurrent operations that might interfere
-- 
-- 3. "VECTOR_SEARCH returns no results"
--    → Ensure index status is ACTIVE before using VECTOR_SEARCH
--    → Verify the query embedding is generated correctly
--    → Check that the embedding column name matches exactly
-- 
-- 4. "Performance not improved"
--    → Vector index is most beneficial for large datasets (10K+ vectors)
--    → For smaller datasets, manual cosine similarity may be faster
--    → Consider the trade-off between speed and precision
-- 
-- 5. "Index maintenance issues"
--    → Vector indexes are automatically maintained by BigQuery
--    → No manual maintenance required
--    → Index is updated when underlying data changes
-- 
-- =================================================================================
-- INDEX SPECIFICATIONS
-- =================================================================================
-- 
-- IVF (Inverted File) Index:
-- - Best for: Large-scale approximate nearest neighbor search
-- - Distance metric: Cosine similarity
-- - Scalability: Handles millions of vectors efficiently
-- - Precision: Approximate (very close to exact results)
-- - Speed: Sub-linear search time
-- 
-- Alternative index types (if needed):
-- - BRUTE_FORCE: Exact search, slower for large datasets
-- - TREE: Good for low-dimensional vectors
-- 
-- =================================================================================
-- NEXT STEPS
-- =================================================================================
-- 
-- After successful index creation:
-- 1. Test semantic search with both methods (07_semantic_search.sql)
-- 2. Implement RAG response generation (08_gemini_rag.sql)
-- 3. Set up new ticket processing workflow (09_new_ticket_flow.sql)
-- 
-- =================================================================================
