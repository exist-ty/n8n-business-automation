-- Источник правды для Notion Auto Documentation. Структура (колонки/типы)
-- всегда живая — берётся из information_schema самим воркфлоу. Здесь —
-- только человеческое описание объекта, которое DB сама предоставить не
-- может; оно единственное, что нужно поддерживать руками при изменениях.
--
-- Осознанно НЕ трогаем schema.sql/marts.sql в etl-portfolio и
-- product-marketing-analytics ради COMMENT ON — это отдельный репозиторий
-- со своей зоной ответственности, каталог описаний живёт здесь.

CREATE TABLE IF NOT EXISTS data_catalog_descriptions (
    object_name TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

INSERT INTO data_catalog_descriptions (object_name, description) VALUES
('mart_sales_summary', 'Агрегат выручки по категории и месяцу (etl-portfolio, батчевый ETL).'),
('mart_channel_economics', 'Юнит-экономика канала по месяцам: CPL, CAC, ROMI, накопительные spend/revenue (product-marketing-analytics/sql/marts.sql).'),
('mart_channel_economics_mv', 'Материализованная версия mart_channel_economics — обновляется через scripts/refresh_marts.py.'),
('mart_customer_ltv', 'LTV клиента: накопительная выручка и порядковый номер заказа через оконные функции.'),
('mart_customer_ltv_mv', 'Материализованная версия mart_customer_ltv.'),
('mart_cohort_retention', 'Помесячный retention по когортам регистрации (cohort-анализ).'),
('mart_cohort_retention_mv', 'Материализованная версия mart_cohort_retention.')
ON CONFLICT (object_name) DO UPDATE SET description = EXCLUDED.description;

-- Запрос, который использует сам воркфлоу (см. workflows/05_notion_auto_documentation.json):
-- живая структура + человеческое описание (каталог выше).
--
-- pg_catalog, а не information_schema.columns: проверено эмпирически —
-- information_schema.columns в PostgreSQL НЕ показывает материализованные
-- представления (relkind='m'), только обычные таблицы и view ('r'/'v') —
-- стандарт SQL появился раньше MATERIALIZED VIEW, и Postgres не стал его
-- ретрофитить. Без этого mart_*_mv выпали бы из документации молча.
SELECT
    c.relname AS table_name,
    d.description AS table_description,
    a.attname AS column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
    a.attnum AS ordinal_position
FROM pg_catalog.pg_class c
JOIN data_catalog_descriptions d ON d.object_name = c.relname
JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
WHERE c.relkind IN ('r', 'v', 'm')
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY c.relname, a.attnum;
