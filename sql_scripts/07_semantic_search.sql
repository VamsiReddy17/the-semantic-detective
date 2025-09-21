-- =================================================================================
-- 07_semantic_search.sql - Semantic Search for Support Tickets
-- =================================================================================
-- Purpose: Implement semantic search functionality to find similar support tickets
--          using vector embeddings and cosine similarity
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- Source Table: insightweaver.hackathon_ai.support_tickets_with_embeddings
-- Model: insightweaver.hackathon_ai.text_embedding_model
-- Index: insightweaver.hackathon_ai.ticket_embedding_index
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- 
-- Prerequisites:
-- 1. Embeddings table created (05_generate_embeddings.sql)
-- 2. Vector index created (06_vector_index.sql) - optional but recommended
-- 3. AI models created (04_models.sql)
-- =================================================================================

-- =================================================================================
-- METHOD 1: Manual Cosine Similarity Search (Exact Results)
-- =================================================================================
-- This method provides exact cosine similarity calculations
-- Best for: Small to medium datasets, when precision is critical
-- Performance: O(n) where n is the number of tickets

-- Example 1: Find tickets similar to a login issue
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. It says invalid credentials.' AS content)
          ) AS e
         ) AS qvec
)
SELECT
  s.ticket_id,
  s.subject,
  s.description,
  s.resolution,
  s.priority,
  s.cust_satisfaction,
  
  -- COSINE SIMILARITY CALCULATION
  -- Formula: dot_product / (norm_query * norm_stored)
  -- Range: 0.0 (completely different) to 1.0 (identical meaning)
  SAFE_DIVIDE(
    -- Dot product: sum of element-wise multiplication
    (SELECT SUM(qv * sv)
     FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
     JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
    ),
    -- Product of vector norms (lengths)
    (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
     SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
    )
  ) AS cosine_similarity

FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
CROSS JOIN query_embedding q
WHERE s.embedding IS NOT NULL
ORDER BY cosine_similarity DESC
LIMIT 5;

-- =================================================================================
-- METHOD 2: Vector Index Search (Fast Approximate Results)
-- =================================================================================
-- This method uses the IVF index for fast approximate nearest neighbor search
-- Best for: Large datasets, when speed is critical
-- Performance: Sub-linear search time

-- Example 2: Same query using vector index (faster for large datasets)
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. It says invalid credentials.' AS content)
          ) AS e
         ) AS query_vector
)
SELECT 
  base.ticket_id,
  base.subject,
  base.description,
  base.resolution,
  base.priority,
  base.cust_satisfaction,
  
  -- Convert distance to similarity (1 - distance)
  -- Lower distance = higher similarity
  1 - distance AS cosine_similarity,
  distance AS raw_distance

FROM VECTOR_SEARCH(
  TABLE `insightweaver.hackathon_ai.support_tickets_with_embeddings`,
  'embedding',
  (SELECT query_vector FROM query_embedding),
  top_k => 5,
  distance_type => 'COSINE'
) AS s
ORDER BY distance ASC;

-- =================================================================================
-- EXAMPLE SEARCHES FOR DIFFERENT USE CASES
-- =================================================================================

-- Example 3: Product-specific issues
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'My GoPro Hero camera is not turning on after charging overnight.' AS content)
          ) AS e
         ) AS qvec
)
SELECT
  s.ticket_id,
  s.subject,
  s.product_purchased,
  s.description,
  s.resolution,
  SAFE_DIVIDE(
    (SELECT SUM(qv * sv)
     FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
     JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
    ),
    (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
     SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
    )
  ) AS cosine_similarity
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
CROSS JOIN query_embedding q
WHERE s.embedding IS NOT NULL
  AND s.product_purchased LIKE '%GoPro%'  -- Filter by product
ORDER BY cosine_similarity DESC
LIMIT 3;

-- Example 4: High-priority unresolved issues
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'Critical system failure causing data loss and customer complaints.' AS content)
          ) AS e
         ) AS qvec
)
SELECT
  s.ticket_id,
  s.subject,
  s.priority,
  s.cust_satisfaction,
  s.description,
  SAFE_DIVIDE(
    (SELECT SUM(qv * sv)
     FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
     JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
    ),
    (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
     SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
    )
  ) AS cosine_similarity
FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
CROSS JOIN query_embedding q
WHERE s.embedding IS NOT NULL
  AND s.priority = 'critical'  -- Filter by priority
  -- Note: status column not available in embeddings table
ORDER BY cosine_similarity DESC
LIMIT 5;

-- =================================================================================
-- ADVANCED SEARCH WITH FILTERING AND RANKING
-- =================================================================================

-- Example 5: Multi-criteria search with custom ranking
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'Customer is very unhappy with slow response time and wants refund.' AS content)
          ) AS e
         ) AS qvec
)
SELECT
  s.ticket_id,
  s.subject,
  s.customer_name,
  s.priority,
  s.cust_satisfaction,
  s.channel,
  
  -- Base similarity score
  SAFE_DIVIDE(
    (SELECT SUM(qv * sv)
     FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
     JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
    ),
    (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
     SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
    )
  ) AS base_similarity,
  
  -- Custom ranking score combining similarity with business factors
  SAFE_DIVIDE(
    (SELECT SUM(qv * sv)
     FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
     JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
    ),
    (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
     SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
    )
  ) * 
  CASE 
    WHEN s.priority = 'critical' THEN 1.2
    WHEN s.priority = 'high' THEN 1.1
    WHEN s.priority = 'medium' THEN 1.0
    ELSE 0.9
  END *
  CASE 
    WHEN s.cust_satisfaction < 3 THEN 1.3  -- Boost low satisfaction tickets
    WHEN s.cust_satisfaction < 4 THEN 1.1
    ELSE 1.0
  END AS weighted_similarity

FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
CROSS JOIN query_embedding q
WHERE s.embedding IS NOT NULL
  -- Note: status column not available in embeddings table
ORDER BY weighted_similarity DESC
LIMIT 10;

-- =================================================================================
-- SEARCH PERFORMANCE ANALYSIS
-- =================================================================================

-- Compare search methods performance
WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. Invalid credentials.' AS content)
          ) AS e
         ) AS qvec
),
manual_search AS (
  SELECT 
    'Manual Cosine' as method,
    s.ticket_id,
    SAFE_DIVIDE(
      (SELECT SUM(qv * sv)
       FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
       SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
      )
    ) AS similarity
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN query_embedding q
  WHERE s.embedding IS NOT NULL
  ORDER BY similarity DESC
  LIMIT 5
)
SELECT 
  method,
  ticket_id,
  ROUND(similarity, 4) as similarity_score,
  ROW_NUMBER() OVER (ORDER BY similarity DESC) as rank
FROM manual_search
ORDER BY similarity DESC;

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- Common issues and solutions:
-- 
-- 1. "No results returned"
--    → Check that embeddings exist: WHERE embedding IS NOT NULL
--    → Verify the query embedding is generated correctly
--    → Ensure the search text is meaningful and not too short
-- 
-- 2. "Low similarity scores"
--    → Similarity scores depend on the quality and diversity of your data
--    → Scores above 0.7 are typically very similar
--    → Scores above 0.5 are reasonably similar
--    → Adjust the LIMIT or add similarity thresholds
-- 
-- 3. "Slow query performance"
--    → Use vector index search (VECTOR_SEARCH) for large datasets
--    → Add appropriate filters to reduce the search space
--    → Consider caching frequently used query embeddings
-- 
-- 4. "Inconsistent results between methods"
--    → Vector index search is approximate, manual search is exact
--    → For small datasets, manual search may be more accurate
--    → For large datasets, vector index search is much faster
-- 
-- 5. "Memory or timeout errors"
--    → Reduce the dataset size with filters
--    → Use vector index search instead of manual calculation
--    -- Increase BigQuery slot allocation if needed
-- 
-- =================================================================================
-- NEXT STEPS
-- =================================================================================
-- 
-- After successful semantic search:
-- 1. Implement RAG response generation (08_gemini_rag.sql)
-- 2. Set up new ticket processing workflow (09_new_ticket_flow.sql)
-- 3. Create a user interface for ticket search
-- 4. Implement search result ranking and filtering
-- 
-- =================================================================================
