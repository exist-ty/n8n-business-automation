-- Weekly AI Business Digest: как и Data Drift Monitor (см.
-- sql/triage_drift_snapshot.sql), сравнивает "прогон к прогону", а не
-- календарную неделю — исходные данные статичны (один ETL-залив), реальной
-- непрерывной по времени истории бизнес-метрик нет. Периодичность в "Weekly"
-- задаётся Cron-триггером внутри n8n, а не тем, что цифры сами меняются раз
-- в неделю.

CREATE TABLE IF NOT EXISTS business_metric_snapshots (
    id SERIAL PRIMARY KEY,
    captured_at TIMESTAMP NOT NULL DEFAULT now(),
    metric_name TEXT NOT NULL,   -- 'romi' | 'avg_ltv' | 'retention_m1'
    metric_key TEXT NOT NULL,    -- канал (для romi) либо 'overall'
    metric_value NUMERIC(12, 4) NOT NULL
);

INSERT INTO business_metric_snapshots (metric_name, metric_key, metric_value)
SELECT 'romi', channel, romi
FROM mart_channel_economics_mv
WHERE spend_month = (SELECT MAX(spend_month) FROM mart_channel_economics_mv)
UNION ALL
SELECT 'avg_ltv', 'overall', ROUND(AVG(final_revenue), 2)
FROM (
    SELECT customer_id, MAX(cumulative_revenue) AS final_revenue
    FROM mart_customer_ltv_mv
    GROUP BY customer_id
) final_ltv_per_customer
UNION ALL
SELECT 'retention_m1', 'overall', retention_rate
FROM mart_cohort_retention_mv
WHERE month_number = 1
  AND cohort_month = (SELECT MAX(cohort_month) FROM mart_cohort_retention_mv WHERE month_number = 1);
