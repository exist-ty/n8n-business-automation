-- Data Drift Monitor хранит снепшоты, а не сравнивает "вчера/сегодня":
-- generate_messages.py/run_triage.py делают TRUNCATE + перезалив на каждый
-- прогон (см. scripts/generate_messages.py) — обычной непрерывной по датам
-- истории тут физически нет, сравнивать есть смысл именно "прогон к прогону".
-- Таблица снепшотов живёт в БД triage (том же контейнере pgvector, порт 5433).

CREATE TABLE IF NOT EXISTS triage_distribution_snapshots (
    id SERIAL PRIMARY KEY,
    captured_at TIMESTAMP NOT NULL DEFAULT now(),
    metric_name TEXT NOT NULL,   -- 'category_pct' | 'avg_confidence' | 'high_priority_pct'
    metric_key TEXT NOT NULL,    -- имя категории, либо 'overall'
    metric_value NUMERIC(6, 4) NOT NULL
);

INSERT INTO triage_distribution_snapshots (metric_name, metric_key, metric_value)
SELECT 'category_pct', category, ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER (), 4)
FROM triage_results
GROUP BY category
UNION ALL
SELECT 'avg_confidence', 'overall', ROUND(AVG(confidence), 4)
FROM triage_results
UNION ALL
SELECT 'high_priority_pct', 'overall', ROUND(COUNT(*) FILTER (WHERE priority = 'high')::numeric / COUNT(*), 4)
FROM triage_results;
