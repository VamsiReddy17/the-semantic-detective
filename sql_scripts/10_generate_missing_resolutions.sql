-- =================================================================================
-- 10_generate_missing_resolutions_working.sql
-- Dual Response Generation (RAG vs Pure-AI) for tickets with missing resolutions
-- - Uses stored embeddings from support_tickets_with_embeddings
-- - Safe cosine similarity (NULLIF denominator)
-- - Uses ml_generate_text_llm_result with FLATTEN_JSON_OUTPUT = TRUE
-- - Produces two rows per ticket: RAG-based and Pure-AI
-- =================================================================================

-- Adjust demo batch size here (remove LIMIT for production)
WITH tickets_missing_resolution AS (
  SELECT 
    ticket_id,
    subject,
    description,
    priority,
    status,
    cust_satisfaction,
    embedding AS ticket_embedding
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings`
  WHERE resolution IS NULL
    AND status = 'open'
    AND embedding IS NOT NULL
  LIMIT 3  -- demo: process 3 tickets. Remove/adjust for production.
),

-- compute similarity between each missing ticket and closed/resolved tickets
similar_scores AS (
  SELECT
    t.ticket_id AS original_ticket_id,
    s.ticket_id AS similar_ticket_id,
    s.subject AS similar_subject,
    s.resolution AS similar_resolution,
    s.priority AS similar_priority,
    s.cust_satisfaction AS similar_satisfaction,
    SAFE_DIVIDE(
      -- dot product
      (SELECT SUM(tv * sv)
       FROM UNNEST(t.ticket_embedding) AS tv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      -- safe norm multiplication
      NULLIF(
        ( SQRT((SELECT SUM(x*x) FROM UNNEST(t.ticket_embedding) AS x)) *
          SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y)) ),
        0
      )
    ) AS similarity_score
  FROM tickets_missing_resolution t
  CROSS JOIN `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  WHERE s.embedding IS NOT NULL
    AND s.resolution IS NOT NULL
    AND s.status = 'closed'
),

-- rank similar tickets per original ticket and keep top-3
top_similar_ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY original_ticket_id ORDER BY similarity_score DESC) AS rn
  FROM similar_scores
),

-- aggregate top-3 into a readable context and compute some metrics
top_similar_agg AS (
  SELECT
    original_ticket_id AS ticket_id,
    COALESCE(
      STRING_AGG(
        CONCAT(
          'Subject: ', COALESCE(similar_subject,'(no subject)'), '\n',
          'Resolution: ', COALESCE(similar_resolution,'(no resolution)'), '\n',
          'Priority: ', COALESCE(CAST(similar_priority AS STRING),''), '\n',
          'CustSat: ', COALESCE(CAST(similar_satisfaction AS STRING),''), '\n',
          'Similarity: ', CAST(ROUND(similarity_score,4) AS STRING),
          '\n---\n'
        ),
        '\n' ORDER BY similarity_score DESC
      ),
      'No similar tickets found.'
    ) AS similar_resolutions_context,
    SAFE_DIVIDE(SUM(similarity_score), NULLIF(COUNT(1),0)) AS avg_similarity_topk,
    MAX(similarity_score) AS max_similarity_topk,
    COUNT(1) AS similar_count
  FROM top_similar_ranked
  WHERE rn <= 3
  GROUP BY original_ticket_id
),

-- join tickets with their context (if none, fallback text is used)
tickets_with_context AS (
  SELECT
    t.*,
    COALESCE(a.similar_resolutions_context, 'No similar tickets found.') AS similar_resolutions_context,
    COALESCE(a.avg_similarity_topk, 0.0) AS avg_similarity_topk,
    COALESCE(a.max_similarity_topk, 0.0) AS max_similarity_topk,
    COALESCE(a.similar_count, 0) AS similar_count
  FROM tickets_missing_resolution t
  LEFT JOIN top_similar_agg a
    ON t.ticket_id = a.ticket_id
)

-- =========================
-- RAG-based responses (uses similar tickets)
-- =========================
SELECT
  'Response Type 1: RAG-based Resolution' AS response_type,
  twc.ticket_id,
  twc.subject,
  twc.description,
  twc.priority,
  twc.status,
  twc.cust_satisfaction,
  twc.similar_resolutions_context AS similar_resolutions_context,
  -- generate text (flattened LLM string)
  (SELECT gen.ml_generate_text_llm_result
   FROM ML.GENERATE_TEXT(
     MODEL `insightweaver.hackathon_ai.text_gen_model`,
     (
       SELECT CONCAT(
         'You are an expert customer support specialist. Use the following similar resolved tickets to craft a practical, step-by-step resolution for the CURRENT TICKET.\n\n',
         'CURRENT TICKET:\n',
         'Subject: ', COALESCE(twc.subject,''), '\n',
         'Description: ', COALESCE(twc.description,''), '\n',
         'Priority: ', COALESCE(CAST(twc.priority AS STRING),''), '\n\n',
         'CONTEXT — TOP SIMILAR RESOLVED TICKETS:\n', COALESCE(twc.similar_resolutions_context,''), '\n\n',
         'INSTRUCTIONS:\n',
         '- Provide concrete troubleshooting steps the customer can perform.\n',
         '- Mention any logs or device information needed.\n',
         '- Include next steps and escalation guidance if unresolved.\n\n',
         'RESOLUTION:'
       ) AS prompt
     ),
     -- generation parameters (increase MAX_OUTPUT_TOKENS if you want longer output)
     STRUCT(1024 AS MAX_OUTPUT_TOKENS, 0.0 AS TEMPERATURE, 0.95 AS TOP_P, 40 AS TOP_K, TRUE AS FLATTEN_JSON_OUTPUT)
   ) AS gen
  ) AS generated_resolution_text,
  'Uses top-3 closed tickets as context' AS data_quality_note,
  twc.similar_count AS similar_tickets_used,
  twc.avg_similarity_topk AS similarity_confidence

FROM tickets_with_context twc
WHERE twc.ticket_id IS NOT NULL

UNION ALL

-- =========================
-- Pure Gemini responses (no external context)
-- =========================
SELECT
  'Response Type 2: Pure Gemini Resolution' AS response_type,
  twc.ticket_id,
  twc.subject,
  twc.description,
  twc.priority,
  twc.status,
  twc.cust_satisfaction,
  'No similar tickets used - pure AI response' AS similar_resolutions_context,
  (SELECT gen.ml_generate_text_llm_result
   FROM ML.GENERATE_TEXT(
     MODEL `insightweaver.hackathon_ai.text_gen_model`,
     (
       SELECT CONCAT(
         'You are an expert customer support specialist for mobile apps.\n\n',
         'CUSTOMER ISSUE:\n',
         'Subject: ', COALESCE(twc.subject,''), '\n',
         'Description: ', COALESCE(twc.description,''), '\n',
         'Priority: ', COALESCE(CAST(twc.priority AS STRING),''), '\n\n',
         'INSTRUCTIONS:\n',
         '- Provide a concise but actionable step-by-step resolution (3-6 steps).\n',
         '- Include mobile-specific troubleshooting (force quit, reinstall, check permissions, OS version, logs to collect).\n',
         '- Specify what additional information the agent should request from the customer.\n\n',
         'RESOLUTION:'
       ) AS prompt
     ),
     STRUCT(1024 AS MAX_OUTPUT_TOKENS, 0.0 AS TEMPERATURE, 0.95 AS TOP_P, 40 AS TOP_K, TRUE AS FLATTEN_JSON_OUTPUT)
   ) AS gen
  ) AS generated_resolution_text,
  'Pure AI response without referencing past resolutions' AS data_quality_note,
  0 AS similar_tickets_used,
  0.0 AS similarity_confidence

FROM tickets_with_context twc
WHERE twc.ticket_id IS NOT NULL

ORDER BY ticket_id, response_type;

-- =================================================================================
-- Optional: Summary statistics (run separately if desired)
-- =================================================================================
/*
SELECT 
  'Resolution Generation Comparison Summary' AS summary_type,
  (SELECT COUNT(*) FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` 
   WHERE resolution IS NULL AND status = 'open') AS open_tickets_without_resolution,
  (SELECT COUNT(*) FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` 
   WHERE resolution IS NOT NULL AND status = 'closed') AS closed_tickets_with_resolution,
  'Demonstrates impact of data quality on AI resolution generation' AS key_learning,
  CURRENT_TIMESTAMP() AS generated_at;
*/

-- =================================================================================
-- Optional update (UNCOMMENT AND RUN SEPARATELY after manual QA)
-- - write generated_resolution_text into a staging column (suggested_resolution)
-- - DO NOT auto-update production `resolution` without review.
-- =================================================================================
/*
-- Example: create staging table first, then insert results from above query into it,
-- review, and then update main table if approved.

-- 1) Create staging table (run once)
CREATE OR REPLACE TABLE `insightweaver.hackathon_ai.suggested_resolutions_staging` AS
SELECT * FROM ( -- paste the full UNION ALL SELECT above ) LIMIT 0;

-- 2) Insert results from the script into the staging table for review.
INSERT INTO `insightweaver.hackathon_ai.suggested_resolutions_staging`
-- paste the SELECT block (without the final ORDER BY) here

-- 3) After review, update main table (example)
UPDATE `insightweaver.hackathon_ai.support_tickets_with_embeddings` t
SET suggested_resolution = s.generated_resolution_text,
    suggested_resolution_source = s.data_quality_note,
    suggested_similarity_confidence = s.similarity_confidence,
    suggested_generated_at = CURRENT_TIMESTAMP()
FROM `insightweaver.hackathon_ai.suggested_resolutions_staging` s
WHERE t.ticket_id = s.ticket_id
  AND s.data_quality_note = 'Uses top-3 closed tickets as context' -- example filter
;
*/