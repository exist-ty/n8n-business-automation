-- Сравнивает два последних снепшота (см. sql/triage_drift_snapshot.sql).
-- FULL OUTER JOIN + COALESCE(...,0), а не INNER JOIN: категория может
-- появиться или исчезнуть между прогонами (генератор синтетики фиксирует
-- 10 категорий, но это не должно быть скрытым допущением запроса).
-- Если снепшот всего один (первый прогон) — previous_value = 0 у всех
-- метрик, и это НЕ реальный дрейф; n8n Code-нода (см. workflows/03_*.json)
-- проверяет количество снепшотов и в этом случае не шлёт ложную тревогу.

WITH ranked_runs AS (
    SELECT captured_at, ROW_NUMBER() OVER (ORDER BY captured_at DESC) AS rn
    FROM (SELECT DISTINCT captured_at FROM triage_distribution_snapshots) d
),
current_run AS (
    SELECT s.metric_name, s.metric_key, s.metric_value
    FROM triage_distribution_snapshots s
    JOIN ranked_runs r ON r.captured_at = s.captured_at AND r.rn = 1
),
previous_run AS (
    SELECT s.metric_name, s.metric_key, s.metric_value
    FROM triage_distribution_snapshots s
    JOIN ranked_runs r ON r.captured_at = s.captured_at AND r.rn = 2
)
SELECT
    COALESCE(c.metric_name, p.metric_name) AS metric_name,
    COALESCE(c.metric_key, p.metric_key) AS metric_key,
    COALESCE(p.metric_value, 0) AS previous_value,
    COALESCE(c.metric_value, 0) AS current_value,
    ROUND(COALESCE(c.metric_value, 0) - COALESCE(p.metric_value, 0), 4) AS delta,
    (SELECT COUNT(DISTINCT captured_at) FROM triage_distribution_snapshots) AS snapshot_count
FROM current_run c
FULL OUTER JOIN previous_run p ON p.metric_name = c.metric_name AND p.metric_key = c.metric_key
ORDER BY ABS(COALESCE(c.metric_value, 0) - COALESCE(p.metric_value, 0)) DESC;
