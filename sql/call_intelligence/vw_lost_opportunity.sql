-- =============================================================================
-- PORTAL AI DATA DEPLOY: CALL INTELLIGENCE
-- Target: gold.vw_lost_opportunity
-- Description: Actionable lost opportunity recovery queue with operational 
--              prioritization (P1/P2/P3) and recommended sales pitch.
-- =============================================================================

SELECT
  f.call_sk,
  f.lead_call_id,
  f.company_id,
  f.call_received_on,
  `pph-central.settings.fn_convert_utc_localtz`(f.call_received_on, f.company_id) AS call_received_on_local,
  DATETIME_DIFF(CURRENT_DATETIME(), DATETIME(`pph-central.settings.fn_convert_utc_localtz`(f.call_received_on, f.company_id)), HOUR) AS hours_since_call,
  
  -- Customer Information
  f.customer_id,
  COALESCE(f.customer_name, 'Cliente No Identificado') AS customer_name,
  f.customer_phone,
  
  -- Operational Context
  f.agent_id,
  f.agent_name,
  f.business_unit_name,
  f.campaign_name,
  f.campaign_category,
  
  -- AI Diagnostics
  f.call_outcome,
  f.lost_reason_category,
  f.service_requested,
  f.price_resistance,
  f.competitor_mentioned,
  f.customer_sentiment,
  f.customer_sentiment_score,
  f.urgency_level,
  f.csr_handling_score,
  f.call_summary,
  f.key_issues,
  
  -- Determined Financial Impact
  f.estimated_opportunity_usd,
  f.valuation_source,
  
  -- Recovery Scoring & Prioritization (Action Motor)
  CASE
    WHEN f.urgency_level IN ('High', 'Emergency') AND f.customer_sentiment_score >= -0.2 THEN 'P1 - URGENTE / ALTA PROBABILIDAD'
    WHEN f.lost_reason_category = 'No Availability' THEN 'P1 - RE-AGENDAR POR DISPONIBILIDAD'
    WHEN f.lost_reason_category = 'Price Objection' THEN 'P2 - OFRECER DESCUENTO / FINANCIAMIENTO'
    WHEN f.lost_reason_category = 'Customer Hesitation' THEN 'P2 - SEGUIMIENTO DE DUDA'
    WHEN f.customer_sentiment = 'Negative' THEN 'P3 - MANEJO ESPECIAL DE CLIENTE MOLESTO'
    ELSE 'P3 - SEGUIMIENTO GENERAL'
  END AS recovery_priority,
  
  -- Actionable Outbound Pitch Recommendation
  CASE
    WHEN f.lost_reason_category = 'No Availability' 
      THEN 'Llamar indicando que se abrio un cupo prioritario en la ruta tecnica para este dia.'
    WHEN f.lost_reason_category = 'Price Objection' 
      THEN 'Contactar ofreciendo promocion de diagnostico o plan de financiamiento sin intereses.'
    WHEN f.lost_reason_category = 'Customer Hesitation' 
      THEN 'Re-contactar para resolver dudas sobre el alcance del servicio y disponibilidad de horarios.'
    WHEN f.lost_reason_category = 'Competitor Shopping' 
      THEN 'Ofrecer garantia de mejor precio y respaldo con tecnicos certificados.'
    ELSE 'Llamar cordialmente para dar seguimiento a la cotizacion y ofrecer asistencia.'
  END AS recommended_pitch,
  
  f.ai_model_version,
  f.transcribed_at
FROM `shape-mhs-1.gold.fc_call_intelligence` f
WHERE f.is_lost_bookable = TRUE
  AND f.job_id IS NULL
  AND f.customer_phone IS NOT NULL;

