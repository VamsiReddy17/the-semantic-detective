-- =================================================================================
-- 09_new_ticket_flow.sql - New Ticket Processing with Dual Response Generation
-- =================================================================================
-- Purpose: Handle new incoming support tickets by generating embeddings,
--          finding similar tickets, and providing TWO types of responses:
--          1. Response based on existing (poor quality) resolutions
--          2. Pure Gemini response without relying on poor quality data
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- =================================================================================

-- =================================================================================
-- STEP 1: New Ticket Analysis and Similarity Matching
-- =================================================================================

WITH new_ticket_embedding AS (
  -- Generate embedding for a simulated new ticket
  SELECT
    ml_generate_embedding_result AS embedding
  FROM ML.GENERATE_EMBEDDING(
    MODEL `insightweaver.hackathon_ai.text_embedding_model`,
    (SELECT 'App crashes immediately after opening' AS content)
  )
),
similar_tickets AS (
  -- Find similar existing tickets with improved similarity calculation
  SELECT
    s.ticket_id,
    s.subject,
    s.description,
    s.resolution,
    s.status,
    s.priority,
    s.cust_satisfaction,
    SAFE_DIVIDE(
      (SELECT SUM(qv * sv)
       FROM UNNEST(nte.embedding) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      NULLIF(
        ( SQRT((SELECT SUM(x*x) FROM UNNEST(nte.embedding) AS x)) *
          SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y)) ),
        0
      )
    ) AS similarity_score
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN new_ticket_embedding nte
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'
    AND s.resolution IS NOT NULL
  ORDER BY similarity_score DESC
  LIMIT 3
)
SELECT 
  'New Ticket Analysis' as analysis_type,
  'NEW_001' as new_ticket_id,
  'App crashes immediately after opening' as new_ticket_subject,
  COUNT(*) as similar_tickets_found,
  MAX(similarity_score) as max_similarity_score,
  AVG(cust_satisfaction) as avg_similar_ticket_satisfaction
FROM similar_tickets;

-- =================================================================================
-- STEP 2: Response Type 1 - Based on Existing (Poor Quality) Resolutions
-- =================================================================================
-- This shows what happens when we rely on poor quality training data

WITH new_ticket_embedding AS (
  SELECT
    ml_generate_embedding_result AS embedding
  FROM ML.GENERATE_EMBEDDING(
    MODEL `insightweaver.hackathon_ai.text_embedding_model`,
    (SELECT 'App crashes immediately after opening' AS content)
  )
),
similar_tickets AS (
  SELECT
    s.ticket_id,
    s.subject,
    s.description,
    s.resolution,
    s.status,
    s.priority,
    s.cust_satisfaction,
    SAFE_DIVIDE(
      (SELECT SUM(qv * sv)
       FROM UNNEST(nte.embedding) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      NULLIF(
        ( SQRT((SELECT SUM(x*x) FROM UNNEST(nte.embedding) AS x)) *
          SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y)) ),
        0
      )
    ) AS similarity_score
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN new_ticket_embedding nte
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'
    AND s.resolution IS NOT NULL
  ORDER BY similarity_score DESC
  LIMIT 3
),
formatted_context AS (
  -- Build RAG prompt using existing (poor quality) resolutions
  SELECT
    CONCAT(
      'You are a helpful, empathetic customer support specialist. ',
      'CURRENT TICKET: Subject: App crashes immediately after opening. ',
      'Description: My iPhone 15 Pro app crashes immediately after opening. ',
      'Priority: High. ',
      'CONTEXT - Similar resolved tickets found: ', CAST(COUNT(*) AS STRING), '. ',
      'INSTRUCTIONS: Provide a clear step-by-step resolution for iPhone 15 Pro app crashes. ',
      'Include troubleshooting steps and mention what information to collect from the customer. ',
      'RESPONSE:'
    ) AS prompt
  FROM similar_tickets
),
generated AS (
  SELECT
    'Response Type 1: Based on Existing Resolutions' AS response_type,
    gen.ml_generate_text_llm_result AS suggested_response
  FROM ML.GENERATE_TEXT(
    MODEL `insightweaver.hackathon_ai.text_gen_model`,
    (SELECT prompt AS PROMPT FROM formatted_context),
    STRUCT(
      512 AS MAX_OUTPUT_TOKENS,
      0.0 AS TEMPERATURE,
      0.95 AS TOP_P,
      40 AS TOP_K,
      TRUE AS FLATTEN_JSON_OUTPUT
    )
  ) AS gen
)
SELECT
  g.response_type,
  g.suggested_response,
  (SELECT COUNT(*) FROM similar_tickets) AS similar_tickets_used,
  (SELECT MAX(similarity_score) FROM similar_tickets) AS max_similarity_score,
  'Based on existing (poor quality) resolutions' AS data_quality_note
FROM generated g;

-- =================================================================================
-- STEP 3: Response Type 2 - Pure Gemini Response (No Poor Quality Data)
-- =================================================================================
-- This shows what happens when we don't rely on poor quality training data

WITH pure_gemini_response AS (
  SELECT
    'Response Type 2: Pure Gemini Response' AS response_type,
    gen.ml_generate_text_llm_result AS suggested_response
  FROM ML.GENERATE_TEXT(
    MODEL `insightweaver.hackathon_ai.text_gen_model`,
    (SELECT 
      'You are an expert customer support specialist for mobile applications. CUSTOMER ISSUE: Subject: App crashes immediately after opening. Description: My iPhone 15 Pro app crashes immediately after opening. I have tried restarting the phone and reinstalling the app, but the issue persists. Priority: High. INSTRUCTIONS: Provide a clear, step-by-step resolution for iPhone 15 Pro app crashes. Include specific troubleshooting steps (force quit, reinstall, iOS version check, storage check). Mention what information to collect from the customer (iOS version, app version, crash logs). Be empathetic and professional. RESPONSE:' AS PROMPT
    ),
    STRUCT(
      512 AS MAX_OUTPUT_TOKENS,
      0.0 AS TEMPERATURE,
      0.95 AS TOP_P,
      40 AS TOP_K,
      TRUE AS FLATTEN_JSON_OUTPUT
    )
  ) AS gen
)
SELECT
  g.response_type,
  g.suggested_response,
  0 AS similar_tickets_used,
  0.0 AS max_similarity_score,
  'Pure Gemini response without poor quality data' AS data_quality_note
FROM pure_gemini_response g;

-- =================================================================================
-- STEP 4: Comparison Summary
-- =================================================================================
-- This provides a summary comparing both response types

WITH comparison_summary AS (
  SELECT
    'Response Comparison Summary' as summary_type,
    'NEW_001' as ticket_id,
    'App crashes immediately after opening' as ticket_subject,
    'high' as priority,
    (SELECT COUNT(*) FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` WHERE status = 'closed') as available_reference_tickets,
    'Demonstrates impact of data quality on AI responses' as key_learning,
    CURRENT_TIMESTAMP() as processed_at
)
SELECT 
  summary_type,
  ticket_id,
  ticket_subject,
  priority,
  available_reference_tickets,
  key_learning,
  processed_at,
  'Two response types generated for comparison' as status
FROM comparison_summary;