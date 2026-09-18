-- =============================================================================
-- PORTAL AI DATA DEPLOY: SERVICE BENCHMARKS (VIEW)
-- Target: gold.vw_service_benchmarks
-- Description: Historical financial benchmarks view calculated dynamically from 
--              ServiceTitan invoicing for real-time deterministic valuation.
-- =============================================================================

WITH invoice_categorized AS (
  SELECT
    id AS invoice_id,
    total AS invoice_total,
    created_on,
    CASE
      WHEN LOWER(job_type) LIKE '%install%' OR LOWER(job_type) LIKE '%replace%' THEN 'HVAC Replacement/Install'
      WHEN LOWER(job_type) LIKE '%tune%' OR LOWER(job_type) LIKE '%maint%' THEN 'Maintenance/Tune-up'
      WHEN LOWER(job_type) LIKE '%water heater%' THEN 'Water Heater'
      WHEN LOWER(job_type) LIKE '%repair%' OR LOWER(job_type) LIKE '%demand%' OR LOWER(job_type) LIKE '%diagnostic%' THEN 'HVAC Repair'
      WHEN LOWER(job_type) LIKE '%electr%' OR LOWER(job_type) LIKE '%sparky%' THEN 'Electrical'
      WHEN LOWER(job_type) LIKE '%plumb%' THEN 'Plumbing General'
      ELSE 'Other'
    END AS service_category
  FROM `shape-mhs-1.silver.vw_invoice`
  WHERE total > 0 AND job_type IS NOT NULL
)
SELECT
  service_category,
  COUNT(*) AS total_invoices_all_time,
  ROUND(SUM(invoice_total), 2) AS total_revenue_all_time,
  ROUND(AVG(invoice_total), 2) AS avg_ticket_all_time_usd,
  ROUND(APPROX_QUANTILES(invoice_total, 100)[OFFSET(50)], 2) AS median_ticket_all_time_usd,
  COUNTIF(created_on >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)) AS total_invoices_365d,
  ROUND(AVG(CASE WHEN created_on >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY) THEN invoice_total END), 2) AS avg_ticket_365d_usd,
  ROUND(APPROX_QUANTILES(CASE WHEN created_on >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY) THEN invoice_total END, 100)[OFFSET(50)], 2) AS median_ticket_365d_usd,
  ROUND(AVG(invoice_total), 2) AS benchmark_ticket_usd,
  CURRENT_TIMESTAMP() AS _etl_synced
FROM invoice_categorized
GROUP BY service_category;

