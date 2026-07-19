-- Аналог sql/readonly_role.sql, но для БД triage (отдельный контейнер
-- pgvector/pgvector, порт 5433, см. llm-practice/docker-compose.yml) —
-- роли не расшарены между разными Postgres-инстансами, поэтому это
-- отдельный скрипт, а не часть readonly_role.sql.
--
-- Только triage_results (category/sentiment/priority/confidence) — НЕ
-- client_messages.message_text: Data Drift Monitor следит за распределением
-- меток, ему не нужен текст обращений клиентов.
--
-- Применить: psql -U postgres -d triage -v n8n_readonly_password='...' -f sql/readonly_role_triage.sql

DROP ROLE IF EXISTS n8n_readonly;
CREATE ROLE n8n_readonly LOGIN PASSWORD :'n8n_readonly_password';

GRANT CONNECT ON DATABASE triage TO n8n_readonly;
GRANT USAGE ON SCHEMA public TO n8n_readonly;
GRANT SELECT ON triage_results TO n8n_readonly;
