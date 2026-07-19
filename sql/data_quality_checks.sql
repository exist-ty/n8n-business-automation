-- AI Data Quality Report: проверки над staging-таблицами после ETL.
-- Выполняется n8n (Postgres node) под ролью n8n_readonly.
--
-- Честная оговорка: часть проверок (PK-дубликаты, NOT NULL на обязательных
-- полях, orphan FK) физически не может ничего найти, пока constraint'ы из
-- etl-portfolio/sql/schema.sql включены — они тут не как "ловушка", а как
-- проверяемая гарантия, что constraint'ы не обошли (например, ручной INSERT
-- мимо src/etl/pipeline.py). Реальные находки стоит ждать от проверок,
-- которые constraint'ы не покрывают: email-дубликаты, NULL в nullable-
-- колонках, отрицательные/нулевые суммы.

SELECT 'row_count' AS check_name, 'stg_customers' AS entity, COUNT(*)::text AS value, (COUNT(*) > 0) AS ok FROM stg_customers
UNION ALL
SELECT 'row_count', 'stg_orders', COUNT(*)::text, (COUNT(*) > 0) FROM stg_orders
UNION ALL
SELECT 'row_count', 'stg_products', COUNT(*)::text, (COUNT(*) > 0) FROM stg_products
UNION ALL
SELECT 'row_count', 'stg_marketing_spend', COUNT(*)::text, (COUNT(*) > 0) FROM stg_marketing_spend

UNION ALL
SELECT 'null_check', 'stg_customers.signup_date', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_customers WHERE signup_date IS NULL
UNION ALL
SELECT 'null_check', 'stg_customers.city', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_customers WHERE city IS NULL

UNION ALL
SELECT 'duplicate_check', 'stg_customers.email', COUNT(*)::text, (COUNT(*) = 0)
FROM (SELECT email FROM stg_customers GROUP BY email HAVING COUNT(*) > 1) dup

UNION ALL
SELECT 'orphan_fk_check', 'stg_orders.customer_id', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_orders o LEFT JOIN stg_customers c ON c.customer_id = o.customer_id WHERE c.customer_id IS NULL
UNION ALL
SELECT 'orphan_fk_check', 'stg_orders.product_id', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_orders o LEFT JOIN stg_products p ON p.product_id = o.product_id WHERE p.product_id IS NULL

UNION ALL
SELECT 'value_range_check', 'stg_orders.total_amount<=0', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_orders WHERE total_amount <= 0
UNION ALL
SELECT 'value_range_check', 'stg_products.price<=0', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_products WHERE price <= 0
UNION ALL
SELECT 'value_range_check', 'stg_marketing_spend.spend<0', COUNT(*)::text, (COUNT(*) = 0)
FROM stg_marketing_spend WHERE spend < 0

ORDER BY check_name, entity;
