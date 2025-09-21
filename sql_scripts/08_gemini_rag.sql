-- =================================================================================
-- 08_gemini_rag.sql - RAG-Based Response Generation with Gemini
-- =================================================================================
-- Purpose: Implement Retrieval-Augmented Generation (RAG) to generate contextual
--          support responses using similar tickets and Gemini text generation
-- 
-- PROJECT CONFIGURATION (insightweaver project):
-- Project ID: insightweaver
-- Dataset: hackathon_ai
-- Source Table: insightweaver.hackathon_ai.support_tickets_with_embeddings
-- Models: insightweaver.hackathon_ai.text_embedding_model
--         insightweaver.hackathon_ai.text_gen_model
-- 
-- FOR NEW USERS:
-- To use this script with your own project, replace:
-- - insightweaver → YOUR_PROJECT_ID
-- - hackathon_ai → YOUR_DATASET_NAME
-- 
-- Prerequisites:
-- 1. Semantic search functionality (07_semantic_search.sql)
-- 2. Text generation model created (04_models.sql)
-- 3. Embeddings table with data (05_generate_embeddings.sql)
-- =================================================================================

-- =================================================================================
-- STEP 1: Basic RAG Response Generation
-- =================================================================================
-- This query demonstrates the core RAG pattern:
-- 1. Retrieve similar tickets using semantic search
-- 2. Format them as context for the LLM
-- 3. Generate a response using Gemini

WITH query_embedding AS (
  -- Generate embedding for the new customer query
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. It says invalid credentials.' AS content)
          ) AS e
         ) AS qvec
),
similar_tickets AS (
  -- Find the most similar tickets using manual cosine similarity
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
       FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
       SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
      )
    ) AS similarity_score
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN query_embedding q
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'  -- Focus on closed tickets for better responses
    AND s.resolution IS NOT NULL
  ORDER BY similarity_score DESC
  LIMIT 3  -- Use top 3 most similar tickets as context
),
formatted_context AS (
  -- Format similar tickets as context for the LLM
  SELECT 
    CONCAT(
      'Based on these similar resolved support tickets, provide a helpful response:\n\n',
      STRING_AGG(
        CONCAT(
          'Ticket ID: ', ticket_id, '\n',
          'Subject: ', subject, '\n',
          'Description: ', description, '\n',
          'Resolution: ', resolution, '\n',
          'Customer Satisfaction: ', CAST(cust_satisfaction AS STRING), '\n',
          'Similarity Score: ', CAST(ROUND(similarity_score, 3) AS STRING), '\n',
          '---'
        ),
        '\n\n'
      ),
      '\n\nNew Customer Query: I cannot log in after the latest app update. It says invalid credentials.\n\n',
      'Please provide a helpful response based on the similar tickets above.'
    ) AS rag_prompt
  FROM similar_tickets
)
-- Generate response using Gemini
SELECT 
  'RAG Response Generation' as response_type,
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS generated_response,
  -- Include metadata about the similar tickets used
  (SELECT COUNT(*) FROM similar_tickets) as similar_tickets_used,
  (SELECT MAX(similarity_score) FROM similar_tickets) as max_similarity_score
FROM ML.GENERATE_TEXT(
  MODEL `insightweaver.hackathon_ai.text_gen_model`,
  (SELECT rag_prompt AS prompt FROM formatted_context)
);

-- =================================================================================
-- STEP 2: Advanced RAG with Product-Specific Context
-- =================================================================================
-- This query enhances RAG by filtering similar tickets by product type

WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'My GoPro Hero camera is not turning on after charging overnight.' AS content)
          ) AS e
         ) AS qvec
),
similar_tickets AS (
  SELECT
    s.ticket_id,
    s.subject,
    s.description,
    s.resolution,
    s.product_purchased,
    s.priority,
    s.cust_satisfaction,
    SAFE_DIVIDE(
      (SELECT SUM(qv * sv)
       FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
       SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
      )
    ) AS similarity_score
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN query_embedding q
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'
    AND s.resolution IS NOT NULL
    AND s.product_purchased LIKE '%GoPro%'  -- Filter by product
  ORDER BY similarity_score DESC
  LIMIT 5
),
formatted_context AS (
  SELECT 
    CONCAT(
      'You are a customer support agent. Based on these similar resolved GoPro support tickets, ',
      'provide a helpful and empathetic response to the customer.\n\n',
      'Similar Tickets:\n',
      STRING_AGG(
        CONCAT(
          'Ticket: ', subject, '\n',
          'Issue: ', description, '\n',
          'Solution: ', resolution, '\n',
          'Customer Rating: ', CAST(cust_satisfaction AS STRING), '/5\n',
          '---'
        ),
        '\n\n'
      ),
      '\n\nCustomer Query: My GoPro Hero camera is not turning on after charging overnight.\n\n',
      'Please provide a step-by-step troubleshooting response that addresses the issue ',
      'and offers additional support options if needed.'
    ) AS rag_prompt
  FROM similar_tickets
)
SELECT 
  'Product-Specific RAG Response' as response_type,
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS generated_response,
  (SELECT COUNT(*) FROM similar_tickets) as similar_tickets_used,
  (SELECT MAX(similarity_score) FROM similar_tickets) as max_similarity_score
FROM ML.GENERATE_TEXT(
  MODEL `insightweaver.hackathon_ai.text_gen_model`,
  (SELECT rag_prompt AS prompt FROM formatted_context)
);

-- =================================================================================
-- STEP 3: RAG with Priority and Satisfaction Weighting
-- =================================================================================
-- This query prioritizes high-satisfaction, high-priority resolved tickets

WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'Critical system failure causing data loss and customer complaints.' AS content)
          ) AS e
         ) AS qvec
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
       FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
       SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
      )
    ) AS base_similarity,
    -- Weighted similarity considering satisfaction and priority
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
      WHEN s.cust_satisfaction >= 4 THEN 1.2  -- Boost high satisfaction
      WHEN s.cust_satisfaction >= 3 THEN 1.0
      ELSE 0.8
    END *
    CASE 
      WHEN s.priority = 'critical' THEN 1.3  -- Boost critical priority
      WHEN s.priority = 'high' THEN 1.1
      ELSE 1.0
    END AS weighted_similarity
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN query_embedding q
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'
    AND s.resolution IS NOT NULL
    AND s.cust_satisfaction >= 3  -- Only use tickets with decent satisfaction
  ORDER BY weighted_similarity DESC
  LIMIT 4
),
formatted_context AS (
  SELECT 
    CONCAT(
      'You are an expert customer support manager handling a critical issue. ',
      'Based on these high-quality resolved tickets, provide an immediate response plan.\n\n',
      'Reference Tickets (sorted by relevance and quality):\n',
      STRING_AGG(
        CONCAT(
          'Priority: ', priority, ' | Satisfaction: ', CAST(cust_satisfaction AS STRING), '/5\n',
          'Issue: ', subject, '\n',
          'Description: ', description, '\n',
          'Successful Resolution: ', resolution, '\n',
          '---'
        ),
        '\n\n'
      ),
      '\n\nCurrent Critical Issue: Critical system failure causing data loss and customer complaints.\n\n',
      'Provide an immediate response plan with:\n',
      '1. Immediate actions to take\n',
      '2. Escalation steps if needed\n',
      '3. Communication plan for affected customers\n',
      '4. Prevention measures for the future'
    ) AS rag_prompt
  FROM similar_tickets
)
SELECT 
  'Priority-Weighted RAG Response' as response_type,
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS generated_response,
  (SELECT COUNT(*) FROM similar_tickets) as similar_tickets_used,
  (SELECT MAX(weighted_similarity) FROM similar_tickets) as max_weighted_similarity
FROM ML.GENERATE_TEXT(
  MODEL `insightweaver.hackathon_ai.text_gen_model`,
  (SELECT rag_prompt AS prompt FROM formatted_context)
);

-- =================================================================================
-- STEP 4: RAG Response Quality Analysis
-- =================================================================================
-- This query analyzes the quality of RAG responses by comparing with actual resolutions

WITH query_embedding AS (
  SELECT (SELECT e.ml_generate_embedding_result
          FROM ML.GENERATE_EMBEDDING(
            MODEL `insightweaver.hackathon_ai.text_embedding_model`,
            (SELECT 'I cannot log in after the latest app update. It says invalid credentials.' AS content)
          ) AS e
         ) AS qvec
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
       FROM UNNEST(q.qvec) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      (SQRT((SELECT SUM(x*x) FROM UNNEST(q.qvec) AS x)) *
       SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
      )
    ) AS similarity_score
  FROM `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  CROSS JOIN query_embedding q
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'
    AND s.resolution IS NOT NULL
  ORDER BY similarity_score DESC
  LIMIT 3
),
rag_response AS (
  SELECT 
    ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS generated_response
  FROM ML.GENERATE_TEXT(
    MODEL `insightweaver.hackathon_ai.text_gen_model`,
    (SELECT 
      CONCAT(
        'Based on these similar resolved support tickets, provide a helpful response:\n\n',
        STRING_AGG(
          CONCAT('Ticket: ', subject, '\nResolution: ', resolution),
          '\n\n'
        ),
        '\n\nNew Customer Query: I cannot log in after the latest app update. It says invalid credentials.\n\n',
        'Please provide a helpful response based on the similar tickets above.'
      ) AS prompt
     FROM similar_tickets)
  )
)
SELECT 
  'RAG Quality Analysis' as analysis_type,
  (SELECT generated_response FROM rag_response) as ai_generated_response,
  (SELECT STRING_AGG(resolution, '\n\n') FROM similar_tickets) as reference_resolutions,
  (SELECT AVG(cust_satisfaction) FROM similar_tickets) as avg_reference_satisfaction,
  (SELECT MAX(similarity_score) FROM similar_tickets) as max_similarity_score,
  (SELECT COUNT(*) FROM similar_tickets) as reference_tickets_count;

-- =================================================================================
-- STEP 5: Batch RAG Processing for Multiple Queries
-- =================================================================================
-- This query demonstrates processing multiple customer queries in batch

WITH customer_queries AS (
  SELECT 
    'login_issue' as query_id,
    'I cannot log in after the latest app update. It says invalid credentials.' as query_text
  UNION ALL
  SELECT 
    'product_issue' as query_id,
    'My GoPro Hero camera is not turning on after charging overnight.' as query_text
  UNION ALL
  SELECT 
    'refund_request' as query_id,
    'I want a refund for my purchase. The product does not work as advertised.' as query_text
),
query_embeddings AS (
  SELECT 
    q.query_id,
    q.query_text,
    (SELECT e.ml_generate_embedding_result
     FROM ML.GENERATE_EMBEDDING(
       MODEL `insightweaver.hackathon_ai.text_embedding_model`,
       (SELECT q.query_text AS content)
     ) AS e
    ) AS query_vector
  FROM customer_queries q
),
similar_tickets_per_query AS (
  SELECT 
    qe.query_id,
    qe.query_text,
    s.ticket_id,
    s.subject,
    s.resolution,
    s.cust_satisfaction,
    SAFE_DIVIDE(
      (SELECT SUM(qv * sv)
       FROM UNNEST(qe.query_vector) AS qv WITH OFFSET pos
       JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
      ),
      (SQRT((SELECT SUM(x*x) FROM UNNEST(qe.query_vector) AS x)) *
       SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
      )
    ) AS similarity_score,
    ROW_NUMBER() OVER (PARTITION BY qe.query_id ORDER BY 
      SAFE_DIVIDE(
        (SELECT SUM(qv * sv)
         FROM UNNEST(qe.query_vector) AS qv WITH OFFSET pos
         JOIN UNNEST(s.embedding) AS sv WITH OFFSET pos USING(pos)
        ),
        (SQRT((SELECT SUM(x*x) FROM UNNEST(qe.query_vector) AS x)) *
         SQRT((SELECT SUM(y*y) FROM UNNEST(s.embedding) AS y))
        )
      ) DESC
    ) as rank
  FROM query_embeddings qe
  CROSS JOIN `insightweaver.hackathon_ai.support_tickets_with_embeddings` s
  WHERE s.embedding IS NOT NULL
    AND s.status = 'closed'
    AND s.resolution IS NOT NULL
),
top_tickets_per_query AS (
  SELECT 
    query_id,
    query_text,
    STRING_AGG(
      CONCAT('Ticket: ', subject, '\nResolution: ', resolution),
      '\n\n'
    ) as context_tickets
  FROM similar_tickets_per_query
  WHERE rank <= 3
  GROUP BY query_id, query_text
)
SELECT 
  'Batch RAG Processing' as processing_type,
  query_id,
  query_text,
  context_tickets,
  -- Generate AI response for each query individually
  CASE 
    WHEN query_id = 'login_issue' THEN
      (SELECT ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] 
       FROM ML.GENERATE_TEXT(
         MODEL `insightweaver.hackathon_ai.text_gen_model`,
         (SELECT CONCAT(
           'You are a customer support agent. Based on these similar resolved support tickets, provide a helpful response to the customer.\n\n',
           'Customer Query: I cannot log in after the latest app update. It says invalid credentials.\n\n',
           'Similar Resolved Tickets:\n', context_tickets, '\n\n',
           'Please provide a helpful response based on the similar tickets above.'
         ) AS prompt)
       ))
    WHEN query_id = 'product_issue' THEN
      (SELECT ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] 
       FROM ML.GENERATE_TEXT(
         MODEL `insightweaver.hackathon_ai.text_gen_model`,
         (SELECT CONCAT(
           'You are a customer support agent. Based on these similar resolved support tickets, provide a helpful response to the customer.\n\n',
           'Customer Query: My GoPro Hero camera is not turning on after charging overnight.\n\n',
           'Similar Resolved Tickets:\n', context_tickets, '\n\n',
           'Please provide a helpful response based on the similar tickets above.'
         ) AS prompt)
       ))
    WHEN query_id = 'refund_request' THEN
      (SELECT ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] 
       FROM ML.GENERATE_TEXT(
         MODEL `insightweaver.hackathon_ai.text_gen_model`,
         (SELECT CONCAT(
           'You are a customer support agent. Based on these similar resolved support tickets, provide a helpful response to the customer.\n\n',
           'Customer Query: I want a refund for my purchase. The product does not work as advertised.\n\n',
           'Similar Resolved Tickets:\n', context_tickets, '\n\n',
           'Please provide a helpful response based on the similar tickets above.'
         ) AS prompt)
       ))
  END AS generated_response
FROM top_tickets_per_query
ORDER BY query_id;

-- =================================================================================
-- TROUBLESHOOTING NOTES
-- =================================================================================
-- 
-- Common issues and solutions:
-- 
-- 1. "No similar tickets found"
--    → Lower the similarity threshold or increase the LIMIT
--    → Check that resolved tickets exist in your dataset
--    → Verify embeddings are properly generated
-- 
-- 2. "Generated response is too generic"
--    → Increase the number of similar tickets used as context
--    → Improve the prompt engineering for more specific instructions
--    → Filter similar tickets by product, priority, or satisfaction
-- 
-- 3. "Response generation fails"
--    → Check that the text generation model is properly configured
--    → Verify the prompt is not too long (Gemini has token limits)
--    → Ensure the connection to Vertex AI is working
-- 
-- 4. "Poor response quality"
--    → Use only high-satisfaction resolved tickets as context
--    → Implement weighted similarity based on ticket quality
--    → Refine the prompt to be more specific about response requirements
-- 
-- 5. "High cost for response generation"
--    → Monitor token usage in Cloud Console
--    → Optimize prompts to be more concise
--    → Consider caching responses for similar queries
-- 
-- =================================================================================
-- NEXT STEPS
-- =================================================================================
-- 
-- After successful RAG implementation:
-- 1. Set up new ticket processing workflow (09_new_ticket_flow.sql)
-- 2. Create a user interface for ticket search and response generation
-- 3. Implement response quality monitoring and feedback loops
-- 4. Set up automated ticket routing based on similarity scores
-- 
-- =================================================================================
