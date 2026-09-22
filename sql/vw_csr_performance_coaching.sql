-- =============================================================================
-- FASE 2: CALL INTELLIGENCE LAKEHOUSE
-- Script 05: gold.vw_csr_performance_coaching
-- Descripción: Vista analítica y de coaching de agentes (CSRs) basada en
--              desempeño real sobre oportunidades calificadas (Bookable Calls).
--              Cumple con la Sección 13 de inicio.txt (control por calidad de leads,
--              dinero perdido por agente, y recomendaciones de coaching por IA).
-- Proyecto: shape-mhs-1 / pph-central
-- =============================================================================

CREATE OR REPLACE VIEW `shape-mhs-1.gold.vw_csr_performance_coaching` AS
WITH agent_aggregations AS (
  SELECT
    agent_id,
    COALESCE(agent_name, 'Sin Asignar / Desconocido') AS agent_name,
    COUNT(*) AS total_calls_handled,
    
    -- Clasificación de Volumen y Oportunidad
    COUNTIF(call_outcome = 'Booked') AS booked_calls,
    COUNTIF(is_lost_bookable = TRUE) AS lost_bookable_calls,
    COUNTIF(call_outcome = 'Booked' OR is_lost_bookable = TRUE) AS total_bookable_opportunities,
    COUNTIF(call_outcome IN ('Inquiry Only', 'Vendor/Spam', 'Other') AND is_lost_bookable = FALSE) AS non_bookable_inquiry_calls,
    
    -- Métricas Financieras Atribuidas
    ROUND(SUM(CASE WHEN is_lost_bookable = TRUE THEN estimated_opportunity_usd ELSE 0 END), 2) AS total_lost_revenue_usd,
    ROUND(AVG(CASE WHEN is_lost_bookable = TRUE THEN estimated_opportunity_usd ELSE NULL END), 2) AS avg_lost_ticket_usd,
    
    -- Comportamientos y Dificultad de Llamada
    COUNTIF(price_resistance = TRUE) AS calls_with_price_resistance,
    COUNTIF(price_resistance = TRUE AND call_outcome = 'Booked') AS price_objections_overcome,
    COUNTIF(competitor_mentioned = TRUE) AS calls_with_competitor_mentioned,
    
    -- Calidad de Atención y Sentimiento (Evaluación Gemini)
    ROUND(AVG(csr_handling_score), 2) AS avg_handling_score,
    ROUND(AVG(customer_sentiment_score), 2) AS avg_customer_sentiment_score,
    
    -- Causa Principal de Pérdida por Agente
    APPROX_TOP_COUNT(CASE WHEN is_lost_bookable = TRUE THEN lost_reason_category ELSE NULL END, 1)[OFFSET(0)].value AS primary_lost_reason
  FROM `shape-mhs-1.gold.fc_call_intelligence`
  GROUP BY agent_id, agent_name
)
SELECT
  agent_id,
  agent_name,
  total_calls_handled,
  total_bookable_opportunities,
  booked_calls,
  lost_bookable_calls,
  non_bookable_inquiry_calls,
  
  -- 1. Tasa de Conversión Real sobre Oportunidades Calificadas (Fair Conversion Rate)
  ROUND(
    SAFE_DIVIDE(booked_calls * 100.0, total_bookable_opportunities), 
    1
  ) AS true_conversion_rate_pct,
  
  -- 2. Tasa de Eficacia en Manejo de Objeción de Precio
  ROUND(
    SAFE_DIVIDE(price_objections_overcome * 100.0, NULLIF(calls_with_price_resistance, 0)), 
    1
  ) AS price_objection_success_rate_pct,
  
  -- 3. Impacto Financiero de la Fuga
  total_lost_revenue_usd,
  avg_lost_ticket_usd,
  
  -- 4. Métricas de Calidad de Voz y Sentimiento
  avg_handling_score,
  avg_customer_sentiment_score,
  primary_lost_reason,
  
  -- 5. Nivel de Desempeño / Segmentación del Agente
  CASE
    WHEN total_bookable_opportunities < 5 THEN 'Bajo Volumen / Muestra Insuficiente'
    WHEN SAFE_DIVIDE(booked_calls * 100.0, total_bookable_opportunities) >= 70.0 AND avg_handling_score >= 8.5 THEN 'Top Performer (Líder de Ventas)'
    WHEN SAFE_DIVIDE(booked_calls * 100.0, total_bookable_opportunities) >= 50.0 THEN 'Consistente / Cumple Estándar'
    ELSE 'Requiere Intervención / Coaching Prioritario'
  END AS performance_tier,
  
  -- 6. Recomendación Automatizada de Coaching (Action Motor 2)
  CASE
    WHEN total_bookable_opportunities < 5 
      THEN 'Continuar monitoreando volumen para consolidar métricas de coaching.'
    WHEN SAFE_DIVIDE(price_objections_overcome * 100.0, NULLIF(calls_with_price_resistance, 0)) < 25.0 AND calls_with_price_resistance >= 3
      THEN 'Capacitar en técnicas de anclaje de valor, explicación de diagnóstico y opciones de financiamiento.'
    WHEN primary_lost_reason = 'Customer Hesitation'
      THEN 'Reforzar técnicas de cierre asistido y ofrecimiento de citas tentativas para asegurar el espacio en agenda.'
    WHEN primary_lost_reason = 'No Availability'
      THEN 'Entrenar en coordinación con despacho para ofrecer ventanas horarias alternativas y lista de espera prioritaria.'
    WHEN avg_handling_score < 7.0
      THEN 'Revisar guion de atención: mejorar escucha activa, empatía y claridad al comunicar la propuesta de servicio.'
    WHEN SAFE_DIVIDE(booked_calls * 100.0, total_bookable_opportunities) >= 70.0
      THEN 'Excelente desempeño. Utilizar grabaciones de este agente como modelo de mejores prácticas para el equipo.'
    ELSE 'Sesión de coaching estándar: revisión de llamadas grabadas con objeciones no resueltas.'
  END AS ai_coaching_recommendation

FROM agent_aggregations;
