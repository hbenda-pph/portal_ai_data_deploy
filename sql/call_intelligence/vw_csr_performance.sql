-- =============================================================================
-- PORTAL AI DATA DEPLOY: CALL INTELLIGENCE
-- Target: gold.vw_csr_performance
-- Description: CSR conversion performance, booking rates, lost opportunities 
--              and handling scores aggregated by agent.
-- =============================================================================

SELECT
  f.company_id,
  COALESCE(f.agent_name, 'Sin Asignar') AS csr_name,
  f.agent_id,
  COUNT(*) AS total_calls_handled,
  COUNTIF(f.call_outcome = 'Booked' OR f.appointment_booked_ai = TRUE) AS booked_calls,
  ROUND(COUNTIF(f.call_outcome = 'Booked' OR f.appointment_booked_ai = TRUE) * 100.0 / NULLIF(COUNT(*), 0), 1) AS booking_conversion_rate,
  COUNTIF(f.is_lost_bookable = TRUE) AS lost_opportunities_count,
  ROUND(COUNTIF(f.is_lost_bookable = TRUE) * 100.0 / NULLIF(COUNT(*), 0), 1) AS lost_rate,
  ROUND(SUM(CASE WHEN f.is_lost_bookable = TRUE THEN f.estimated_opportunity_usd ELSE 0 END), 2) AS total_revenue_at_risk_usd,
  ROUND(AVG(f.customer_sentiment_score), 2) AS avg_customer_sentiment,
  ROUND(AVG(f.csr_handling_score), 2) AS avg_csr_handling_score,
  COUNTIF(f.price_resistance = TRUE) AS price_resistance_calls_count,
  COUNTIF(f.competitor_mentioned = TRUE) AS competitor_mentioned_calls_count
FROM `shape-mhs-1.gold.vw_call_intelligence` f
WHERE f.agent_name IS NOT NULL
GROUP BY f.company_id, csr_name, f.agent_id;

