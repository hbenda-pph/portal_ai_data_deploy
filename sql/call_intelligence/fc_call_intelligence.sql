-- =============================================================================
-- PORTAL AI DATA DEPLOY: CALL INTELLIGENCE
-- Target: gold.fc_call_intelligence
-- Description: Canonical call intelligence fact table reconciling ServiceTitan 
--              calls, jobs, customer data, and Gemini AI transcriptions.
-- =============================================================================

WITH dedup_calls AS (
  SELECT 
    c.lead_call_id,
    c.project_id AS company_id,
    c.lead_call_received_on AS call_received_on,
    SAFE_CAST(c.lead_call_duration AS FLOAT64) AS call_duration_seconds,
    c.lead_call_direction AS call_direction,
    c.lead_call_customer_id AS customer_id,
    c.lead_call_from AS customer_phone,
    c.lead_call_agent_id AS agent_id,
    c.lead_call_agent_name AS agent_name,
    c.campaign_id,
    c.business_unit_id,
    c.job_number,
    ROW_NUMBER() OVER (
      PARTITION BY c.lead_call_id 
      ORDER BY 
        (c.business_unit_id IS NOT NULL) DESC,
        (c.lead_call_agent_name IS NOT NULL) DESC,
        c.lead_call_received_on DESC
    ) AS rn
  FROM `shape-mhs-1.silver.vw_call` c
  WHERE c.lead_call_id IS NOT NULL
),
raw_calls AS (
  SELECT * EXCEPT(rn) FROM dedup_calls WHERE rn = 1
),
dedup_recordings AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (
      PARTITION BY lead_call_id 
      ORDER BY transcribed_at DESC, _etl_synced DESC
    ) AS rn
  FROM `shape-mhs-1.silver.tb_call_recordings`
  WHERE lead_call_id IS NOT NULL
),
raw_recordings AS (
  SELECT * EXCEPT(rn) FROM dedup_recordings WHERE rn = 1
),
dedup_jobs AS (
  SELECT 
    lead_call_id,
    id AS job_id,
    job_number,
    booking_id,
    job_status,
    ROW_NUMBER() OVER (PARTITION BY lead_call_id ORDER BY created_on DESC) AS rn
  FROM `shape-mhs-1.silver.vw_job`
  WHERE lead_call_id IS NOT NULL
),
open_estimates AS (
  SELECT
    customer_id,
    subtotal AS estimate_subtotal,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_on DESC) AS rn
  FROM `shape-mhs-1.silver.vw_estimate`
  WHERE status_name IN ('Open', 'Dismissed') AND subtotal > 0
),
enriched AS (
  SELECT
    TO_HEX(SHA256(CONCAT(CAST(COALESCE(c.company_id, 1) AS STRING), '_', CAST(c.lead_call_id AS STRING)))) AS call_sk,
    c.lead_call_id,
    COALESCE(c.company_id, 1) AS company_id,
    c.call_received_on,
    c.call_duration_seconds,
    c.call_direction,
    c.customer_id,
    cust.name AS customer_name,
    c.customer_phone,
    c.agent_id,
    c.agent_name,
    c.campaign_id,
    cmp.name AS campaign_name,
    cmp.category_name AS campaign_category,
    c.business_unit_id,
    bu.name AS business_unit_name,
    j.job_id,
    COALESCE(j.job_number, c.job_number) AS job_number,
    j.booking_id,
    j.job_status,
    (t.lead_call_id IS NOT NULL) AS is_transcribed,
    t.transcription AS transcription_text,
    t.summary AS call_summary,
    t.call_outcome,
    t.lost_reason_category,
    t.service_requested_category AS service_requested,
    t.appointment_booked AS appointment_booked_ai,
    t.price_resistance_detected AS price_resistance,
    t.competitor_mentioned,
    t.customer_sentiment,
    t.customer_sentiment_score,
    t.urgency_level,
    t.csr_handling_score,
    COALESCE(t.key_issues, []) AS key_issues,
    
    -- Action Motor 1: Deterministic Lost Opportunity flag
    CASE 
      WHEN t.call_outcome = 'Lost Opportunity' THEN TRUE
      WHEN t.appointment_booked = FALSE 
           AND t.service_requested_category IS NOT NULL 
           AND t.lost_reason_category NOT IN ('None', 'Vendor/Spam', 'Other')
           AND j.job_id IS NULL THEN TRUE
      ELSE FALSE
    END AS is_lost_bookable,
    
    -- Financial Valuation (Open Estimates -> Historical Benchmarks -> Default)
    CASE 
      WHEN est.estimate_subtotal IS NOT NULL THEN est.estimate_subtotal
      WHEN bm.benchmark_ticket_usd IS NOT NULL THEN bm.benchmark_ticket_usd
      ELSE 3450.0
    END AS estimated_opportunity_usd,
    CASE 
      WHEN est.estimate_subtotal IS NOT NULL THEN 'OPEN_ESTIMATE_SERVICETITAN'
      WHEN bm.benchmark_ticket_usd IS NOT NULL THEN 'BENCHMARK_HISTORICAL_INVOICE'
      ELSE 'BENCHMARK_DEFAULT'
    END AS valuation_source,
    
    t.model_version AS ai_model_version,
    t.transcribed_at,
    CURRENT_TIMESTAMP() AS _etl_synced
  FROM raw_calls c
  LEFT JOIN raw_recordings t ON c.lead_call_id = t.lead_call_id
  LEFT JOIN `shape-mhs-1.silver.vw_customer` cust ON c.customer_id = cust.id
  LEFT JOIN `shape-mhs-1.bronze.campaign` cmp ON c.campaign_id = cmp.id
  LEFT JOIN `shape-mhs-1.bronze.business_unit` bu ON c.business_unit_id = bu.id
  LEFT JOIN (SELECT * EXCEPT(rn) FROM dedup_jobs WHERE rn = 1) j ON c.lead_call_id = j.lead_call_id
  LEFT JOIN (SELECT * EXCEPT(rn) FROM open_estimates WHERE rn = 1) est ON c.customer_id = est.customer_id
  LEFT JOIN `shape-mhs-1.gold.dm_service_benchmarks` bm ON t.service_requested_category = bm.service_category
)
SELECT * FROM enriched;

