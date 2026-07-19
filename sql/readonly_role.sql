-- Роль только для чтения для n8n-воркфлоу (Data Drift Monitor, AI Data
-- Quality Report, Self-Service Analytics Bot), отдельная от postgres-
-- суперпользователя, которым пользуются ETL/ML-скрипты. n8n получает
-- SELECT только на аналитические витрины — НЕ на stg_customers.email/name
-- напрямую: self-service бот не должен уметь прочитать PII в принципе,
-- а не полагаться на то, что модель "не спросит" (см. docs/self-service-bot-security.md).
--
-- Применить: psql -U postgres -d etl_portfolio -v n8n_readonly_password='...' -f sql/readonly_role.sql

DROP ROLE IF EXISTS n8n_readonly;
CREATE ROLE n8n_readonly LOGIN PASSWORD :'n8n_readonly_password';

GRANT CONNECT ON DATABASE etl_portfolio TO n8n_readonly;
GRANT USAGE ON SCHEMA public TO n8n_readonly;

-- Витрины для Weekly AI Business Digest и Self-Service Analytics Bot
GRANT SELECT ON mart_sales_summary TO n8n_readonly;
GRANT SELECT ON mart_channel_economics TO n8n_readonly;
GRANT SELECT ON mart_channel_economics_mv TO n8n_readonly;
GRANT SELECT ON mart_customer_ltv TO n8n_readonly;
GRANT SELECT ON mart_customer_ltv_mv TO n8n_readonly;
GRANT SELECT ON mart_cohort_retention TO n8n_readonly;
GRANT SELECT ON mart_cohort_retention_mv TO n8n_readonly;

-- AI Data Quality Report считает только COUNT/агрегаты по staging-таблицам
-- (NULL/дубликаты/orphan FK/row count) — сам email/name в ответ не попадает,
-- см. sql/data_quality_checks.sql
GRANT SELECT ON stg_customers TO n8n_readonly;
GRANT SELECT ON stg_orders TO n8n_readonly;
GRANT SELECT ON stg_products TO n8n_readonly;
GRANT SELECT ON stg_marketing_spend TO n8n_readonly;

-- Notion Auto Documentation (workflows/05_*.json) читает описания объектов
-- отсюда — таблица создаётся вручную (sql/data_catalog.sql) под
-- postgres, не под n8n_readonly, поэтому грант не наследуется автоматически
GRANT SELECT ON data_catalog_descriptions TO n8n_readonly;
