-- Отдельная, ЕЩЁ более узкая роль для Self-Service Analytics Bot —
-- отдельная от n8n_readonly (см. sql/readonly_role.sql), которая нужна
-- Data Quality Report для проверок NULL/дубликатов на stg_customers.email
-- и т.п. Бот принимает натуральный язык от менеджеров, а не доверенный
-- SQL инженера — поверхность атаки другая, и роль должна быть уже, а не
-- переиспользовать n8n_readonly просто потому что "тоже read-only".
--
-- Три независимых слоя защиты (см. docs/self-service-bot-security.md):
--   1) GRANT только на агрегированные витрины — ни stg_customers.email,
--      ни stg_customers.name физически недостижимы этой ролью, даже если
--      LLM сгенерирует SELECT * FROM stg_customers или JOIN на неё.
--   2) default_transaction_read_only=on — блокирует запись на уровне
--      транзакции, а не только через отсутствие GRANT (страховка от
--      SECURITY DEFINER функций и подобных обходов).
--   3) statement_timeout='5s' — обрезает "SELECT pg_sleep(999)"-класс
--      DoS, который GRANT-модель сама по себе не ловит (это легальный SELECT).
-- Валидация SQL на стороне n8n (workflows/06_self_service_analytics_bot.json)
-- — это доп. слой для быстрого дружелюбного отказа, а не единственная
-- защита: даже если её обойти, роль всё равно не может ничего, кроме
-- SELECT по 7 перечисленным ниже объектам.
--
-- Применить: psql -U postgres -d etl_portfolio -v n8n_selfservice_password='...' -f sql/readonly_role_selfservice.sql

DROP ROLE IF EXISTS n8n_selfservice;
CREATE ROLE n8n_selfservice LOGIN PASSWORD :'n8n_selfservice_password';
ALTER ROLE n8n_selfservice SET statement_timeout = '5s';
ALTER ROLE n8n_selfservice SET default_transaction_read_only = on;

GRANT CONNECT ON DATABASE etl_portfolio TO n8n_selfservice;
GRANT USAGE ON SCHEMA public TO n8n_selfservice;

GRANT SELECT ON mart_sales_summary TO n8n_selfservice;
GRANT SELECT ON mart_channel_economics TO n8n_selfservice;
GRANT SELECT ON mart_channel_economics_mv TO n8n_selfservice;
GRANT SELECT ON mart_customer_ltv TO n8n_selfservice;
GRANT SELECT ON mart_customer_ltv_mv TO n8n_selfservice;
GRANT SELECT ON mart_cohort_retention TO n8n_selfservice;
GRANT SELECT ON mart_cohort_retention_mv TO n8n_selfservice;
