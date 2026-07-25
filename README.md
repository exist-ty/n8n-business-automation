# n8n Business Automation

Слой бизнес-автоматизации поверх остальной экосистемы
([etl-portfolio](https://github.com/exist-ty/etl-portfolio), [product-marketing-analytics](https://github.com/exist-ty/product-marketing-analytics),
[support-triage-llm](https://github.com/exist-ty/support-triage-llm), оркестрируются через
[Nikolay-Kolesnikov-portfolio-hub](https://github.com/exist-ty/Nikolay-Kolesnikov-Data-Engineering-Applied-ML-LLM-Portfolio-Hub)/Airflow).
Airflow оркестрирует пайплайны данных; n8n — это то, что происходит
**вокруг** пайплайнов и обращено к людям: алерты, дайджесты, разговорный
доступ к аналитике. Разделение осознанное — Airflow и n8n НЕ дублируют
друг друга (см. "Почему n8n, а не только Airflow" ниже).

## Стек

- **n8n** 2.30.7 (Docker, `docker.n8n.io/n8nio/n8n`), хранилище — SQLite
  в volume (не нужен отдельный Postgres для самого n8n — это несколько
  cron/webhook-триггеров, а не нагруженное веб-приложение)
- **PostgreSQL** — тот же `etl_portfolio` и `triage`, что и у остальных
  репозиториев, но под тремя новыми, специально ограниченными ролями
  (см. "Безопасность" ниже)
- **Ollama** (qwen2.5:3b-instruct) — та же локальная LLM, что и в
  support-triage-llm, для AI-сводки дайджеста и NL→SQL в боте (backend по
  умолчанию)
- **Groq API** (Llama 3.3 70B Instruct) — опциональный облачный backend для
  AI-сводки дайджеста (`DIGEST_LLM_BACKEND=groq`, workflow 04) — см.
  «Локально vs облако» ниже
- **Telegram Bot API**, **SMTP**, **Notion API** — каналы доставки

## Почему n8n, а не только Airflow

Оба — оркестраторы, и добавление второго ради второго было бы
избыточностью без причины. Разделение по типу задачи: Airflow — батчевый,
DAG-ориентированный, знает про порядок и повторные попытки внутри
пайплайна данных. То, что здесь — event-driven обвязка вокруг него:
уведомления, дайджесты, разговорный интерфейс. Пример конкретного
разделения: Airflow **не знает**, что делать с "если ETL упал — напиши
в Telegram и на почту" — это не задача трансформации данных, это
маршрутизация уведомления в конкретный канал с конкретным форматированием.
Дублирования нет: ни один воркфлоу здесь не переделывает то, что уже
делает Airflow-DAG, каждый вызывается ИЗ него через webhook.

## Структура

```
docker-compose.yml               # n8n, порт 5678
sql/
  readonly_role.sql              # n8n_readonly: витрины + stg_* (для Quality Report)
  readonly_role_triage.sql       # n8n_readonly в БД triage (Drift Monitor)
  readonly_role_selfservice.sql  # n8n_selfservice: ТОЛЬКО витрины (для бота)
  data_quality_checks.sql
  triage_drift_snapshot.sql / triage_drift_diff.sql
  business_digest_snapshot.sql / business_digest_diff.sql
  data_catalog.sql
workflows/                       # экспортированные n8n workflow JSON (workflow-as-code)
  01_etl_failure_alert.json
  02_ai_data_quality_report.json
  03_data_drift_monitor.json
  04_weekly_ai_business_digest.json
  05_notion_auto_documentation.json
  06_self_service_analytics_bot.json
docs/
  self-service-bot-security.md       # модель угроз, что реально гарантировано
  security_model.md                  # тот же бот через STRIDE — что покрыто, что нет
  manager-guide-self-service-bot.md  # инструкция для менеджеров простым языком
```

## Как запустить

```bash
cp .env.example .env
# заполнить N8N_ENCRYPTION_KEY (python -c "import secrets; print(secrets.token_hex(16))"),
# пароли для трёх ролей, TELEGRAM_ALERT_CHAT_ID, ALERT_EMAIL_*

docker compose up -d

# применить роли к реальным БД (psql или любой Postgres-клиент):
psql -U postgres -d etl_portfolio -v n8n_readonly_password="'...'" -f sql/readonly_role.sql
psql -U postgres -d etl_portfolio -v n8n_selfservice_password="'...'" -f sql/readonly_role_selfservice.sql
psql -U postgres -d triage -v n8n_readonly_password="'...'" -f sql/readonly_role_triage.sql

# импортировать воркфлоу (workflow-as-code, не через UI):
docker exec <container> n8n import:workflow --input=/workflows/01_etl_failure_alert.json
# ...аналогично для 02-06

# credentials (Postgres/Telegram/SMTP/Notion) — через n8n import:credentials
# с JSON, который НЕ должен попадать в git (см. "Credentials" ниже)

# активировать нужные воркфлоу:
docker exec <container> n8n update:workflow --id=<id> --active=true
docker compose restart n8n  # активация применяется только после рестарта
```

## Шесть воркфлоу

| # | Воркфлоу | Триггер | Статус проверки |
|---|----------|---------|------------------|
| 1 | ETL Failure Alert | Airflow `on_failure_callback` → webhook | ✅ реальный Telegram-алерт получен |
| 2 | AI Data Quality Report | Airflow, после `etl_pipeline` → webhook | ✅ реальный Telegram-алерт получен |
| 3 | Data Drift Monitor | Airflow, после `evaluate_llm` → webhook | ✅ SQL проверен на реальных данных (см. ниже) |
| 4 | Weekly AI Business Digest | n8n Cron (понедельник, 8:00) | ✅ SQL + Ollama-сводка проверены на реальных данных; облачный backend (Llama 3.3 70B, Groq) — HTTP-вызов проверен вживую из контейнера n8n, полный прогон по cron ещё не тестировался (см. «Локально vs облако» ниже) |
| 5 | Notion Auto Documentation | Airflow, после `refresh_marts` → webhook | ✅ реальная страница в Notion обновлена вживую (см. ниже) |
| 6 | Self-Service Analytics Bot | Telegram-сообщение боту | ✅ NL→SQL→выполнение проверены реальными вызовами Ollama + Postgres (см. ниже) |

Для (1)-(3), (5) в DAG хаба добавлены соответствующие точки интеграции
(`on_failure_callback`, `notify_quality_report`, вызов `triage-drift-check`
после `evaluate_llm`, `docs-refresh` после `refresh_marts`) — n8n дергается
webhook'ом изнутри Airflow, а не наоборот.

**Важное отличие (6) от остальных**: Telegram Trigger (в отличие от
обычной Webhook-ноды) регистрирует вебхук НЕПОСРЕДСТВЕННО у Telegram —
для этого n8n должен быть доступен по публичному HTTPS, `localhost` не
годится. Для локальной разработки/демо это решается временным туннелем
(`ngrok http 5678`, `WEBHOOK_URL=https://<...>.ngrok-free.dev/` в
окружении n8n) — не персистентная часть конфигурации, поднимается только
на время живого теста. `cloudflared` (Cloudflare Tunnel) в этой сети не
сработал — исходящий трафик на порт 7844 (и QUIC, и TCP/HTTP2-фолбэк)
оказался заблокирован файрволом, что подтвердил встроенный precheck
самого `cloudflared`; `ngrok` (порт 443, отдельная инфраструктура)
сработал без проблем.

## Локально vs облако: AI-сводка дайджеста

Workflow 04 (Weekly AI Business Digest) по умолчанию суммирует изменения
бизнес-метрик локальной Qwen2.5-3B-Instruct через Ollama — без единого
внешнего API-вызова. Добавлен второй вариант: `DIGEST_LLM_BACKEND=groq` в
`.env` переключает узел `Backend switch` на `Llama 3.3 70B summary (Groq)`
вместо `Ollama AI summary` — тот же промпт (агрегированные значения
ROMI/LTV/retention и их изменение к прошлому запуску), тот же дальнейший
шаг `Format digest`, который теперь понимает оба формата ответа (Ollama
`{response}` и OpenAI-совместимый `{choices[0].message.content}` у Groq).

**Данные.** Промпт содержит только агрегированные бизнес-метрики
(ROMI по каналам, средний LTV, retention) — не персональные данные
конкретных клиентов. При `DIGEST_LLM_BACKEND=groq` этот текст уходит по
HTTPS на инфраструктуру Groq с ключом из `GROQ_API_KEY` (заголовок
`Authorization: Bearer ...`, см. узел `groq-summary` в
`workflows/04_weekly_ai_business_digest.json`) — при локальном Ollama
ничего не покидает машину. Осознанный выбор, а не побочный эффект смены
конфига.

**Статус:** сам HTTP-вызов проверен вживую изнутри контейнера n8n — тот же
запрос (модель, заголовок `Authorization`, тело), что делает узел
`groq-summary`, с реальным `GROQ_API_KEY` из окружения контейнера, получил
настоящий ответ от Groq за 0.09 сек (`total_time` в ответе API). Полный
прогон воркфлоу через движок n8n (по реальному cron-триггеру, с настоящими
`business_metric_snapshots`) отдельно не тестировался — это разные вещи:
первое подтверждает, что интеграция и авторизация работают, второе — что
весь пайплайн (Postgres → prompt → LLM → Telegram/Email) отрабатывает
end-to-end.

## Честные результаты тестирования

### 1-2: реальная доставка в Telegram

Оба воркфлоу реально протриггерены через `curl -X POST
http://localhost:5678/webhook/...`, статус выполнения в БД n8n —
`success` (не просто "не упало", а дошло до отправки). По ходу нашёл и
исправил два реальных препятствия, а не гипотетических:
- n8n по умолчанию блокирует `$env` в нодах/выражениях
  (`N8N_BLOCK_ENV_ACCESS_IN_NODE`) — защита от воркфлоу недоверенного
  автора; здесь единственный автор воркфлоу — я сам, риск неприменим.
- Git Bash (MSYS) на Windows манглит Unix-style пути в `docker exec`
  (`/workflows/...` → `C:/Program Files/Git/workflows/...`) — тот же
  баг, что уже встречался с Airflow, фикс — `MSYS_NO_PATHCONV=1`.

### 3-4: run-over-run вместо day-over-day

`generate_messages.py`/ETL делают `TRUNCATE` + перезалив на каждый
прогон (см. схемы соответствующих репозиториев) — непрерывной по
календарным датам истории физически нет. Data Drift Monitor и Weekly
Digest поэтому хранят снепшоты метрик (`triage_distribution_snapshots`,
`business_metric_snapshots`) и сравнивают "прогон к прогону", а не "день
к дню" — честно задокументировано в самих SQL-файлах. SQL проверен на
реальных данных: первый снепшот корректно не считается "дрейфом"
(`snapshot_count < 2` → сообщение не шлётся), два одинаковых снепшота
подряд корректно дают дельту 0.0000 по всем метрикам.

### Важный побочный найденный баг: `information_schema.columns` не видит materialized view

При проверке `sql/data_catalog.sql` на реальной БД обнаружилось, что
`information_schema.columns` в PostgreSQL **не показывает материализованные
представления** (`relkind='m'`) — только обычные таблицы и view. Стандарт
SQL появился раньше `MATERIALIZED VIEW`, и Postgres не стал его
ретрофитить. `mart_*_mv` объекты молча выпадали бы из документации.
Исправлено переходом на `pg_catalog.pg_class`/`pg_attribute` напрямую
(покрывает `relkind IN ('r','v','m')`) — проверено: 7 из 7 объектов
каталога теперь находятся корректно (было 4 из 7).

### 6: Self-Service Analytics Bot — самое интересное

Три независимых слоя защиты (см. `docs/self-service-bot-security.md`, а
также `docs/security_model.md` — тот же бот, разложенный по STRIDE, где
честно отмечен один непокрытый пробел — Spoofing/отсутствие allowlist чатов)
проверены эмпирически на реальной БД под ролью `n8n_selfservice`:

| Проверка | Результат |
|---|---|
| `SELECT` по разрешённой витрине | ✅ выполнился |
| `SELECT email FROM stg_customers` | ✅ `permission denied for table stg_customers` |
| `INSERT` | ✅ `cannot execute INSERT in a read-only transaction` |
| `SELECT pg_sleep(10)` | ✅ прерван через ровно 5.0s (`statement_timeout`) |

NL→SQL протестирован реальными вызовами `qwen2.5:3b-instruct` через
Ollama. **Нашёл нетривиальный факт**: с инструкциями на русском модель
почти всегда отвечала `NOT_POSSIBLE` даже на решаемые вопросы; с
инструкциями на английском (вопрос менеджера при этом остаётся на
русском) — все 3 тестовых бизнес-вопроса дали корректный, безопасный SQL,
а провокационный "покажи email всех клиентов" корректно получил
`NOT_POSSIBLE` уже на уровне самой модели (до похода в БД, где это и так
физически невозможно). Промпт в `workflows/06_*.json` использует
английские инструкции по этой причине.

Ещё одна честная находка при исполнении сгенерированных запросов:
на вопрос "какой канал показал лучший ROMI в последнем месяце" модель
сгенерировала синтаксически корректный, безопасный, но **пустой по
результату** запрос (`WHERE spend_month = CURRENT_DATE - INTERVAL '1
month'`) — потому что данные статичны (последний реальный месяц —
2025-05, а не "сейчас"), а модель об этом не знает. Валидация
гарантирует безопасность запроса, но не его смысловую корректность —
разница описана в `docs/self-service-bot-security.md` и вынесена в
пользовательские рекомендации `docs/manager-guide-self-service-bot.md`.
Два других вопроса ("топ-5 категорий по выручке", "средний retention на
первый месяц") отработали корректно и вернули реальные цифры.

### Живой прогон через настоящий Telegram (не через curl) — что нашлось

После настройки временного публичного туннеля (ngrok, т.к. `cloudflared`
оказался заблокирован сетью на уровне порта 7844 — честно
задокументированный тупик, не гипотетический) бот реально отвечал на
сообщения из Telegram. Три находки, все — реальные, не придуманные:

1. **"Покажи топ-5 категорий товаров по выручке"** — бот ответил, но
   результат содержал повторяющиеся названия категорий (`Books`,
   `Toys`, `Toys`, `Books`, `Books`) вместо 5 РАЗНЫХ категорий: модель
   сгенерировала `SELECT category, total_revenue FROM
   mart_sales_summary ORDER BY total_revenue DESC LIMIT 5` — это топ-5
   строк исходной таблицы (по паре категория+месяц), а не топ-5
   категорий, просуммированных по всем месяцам. Запрос безопасен и
   технически корректен, но отвечает не совсем на тот вопрос, что был
   задан. Добавлена оговорка в `docs/manager-guide-self-service-bot.md`.
2. **"Сколько мы тратим на email-рассылки?"** — при первом
   ручном тесте через Ollama (см. выше) модель ответила корректным SQL;
   на живом прогоне через Telegram тот же класс вопроса получил
   `NOT_POSSIBLE`, хотя данные (канал `email` в
   `mart_channel_economics_mv`) доступны. Нестабильность малой модели
   между запусками — убрал этот пример из списка "точно работающих" в
   гайде для менеджеров, добавил честную оговорку вместо него.
3. **Нашёл и исправил реальный баг форматирования ошибок**: при
   реальном сбое запроса к базе бот показывал нечитаемое `⚠️ Запрос к
   базе не выполнился: object Object` — Code-нода `Format results`
   ожидала `error.message`, а Postgres-нода при `continueOnFail` не
   всегда кладёт ошибку именно в это поле. Исправлено на устойчивое
   приведение к строке (`message` → `description` → `JSON.stringify` →
   `String()`).

## Безопасность: три роли, разная поверхность атаки

- **`n8n_readonly`** (`sql/readonly_role.sql`, `sql/readonly_role_triage.sql`)
  — витрины + `stg_*`/`triage_results`. Вызывающая сторона — Airflow
  (доверенный, детерминированный код), поэтому шире.
- **`n8n_selfservice`** (`sql/readonly_role_selfservice.sql`) — ТОЛЬКО 7
  агрегированных витрин, `default_transaction_read_only=on`,
  `statement_timeout='5s'`. Вызывающая сторона — LLM по недоверенному
  натуральному языку, поэтому уже. Подробности и обоснование каждого
  слоя — `docs/self-service-bot-security.md`.

## Credentials

Реальные секреты (Telegram bot token, SMTP-пароль, Notion integration
token) никогда не пишутся в файлы репозитория — импортируются в n8n
через `n8n import:credentials` из временного JSON вне репозитория,
который удаляется сразу после импорта. `.env` (пароли Postgres-ролей,
chat_id, email-адреса) в `.gitignore`.

Что нужно для полного живого прогона всех 6 воркфлоу:
- ✅ Telegram bot token + chat_id — есть, воркфлоу 1/2/5/6 реально
  протестированы вживую
- ⏳ SMTP (адрес + пароль) — не настроено, email-доставка не проверена
- ✅ Notion integration token + ID страницы — есть, воркфлоу 5 реально
  обновил живую страницу (см. "Живой прогон Notion Auto Documentation" ниже)

### Живой прогон Notion Auto Documentation

Целевая страница создана заранее (вручную, через Notion MCP — не через
сам воркфлоу, это разные пути доступа: MCP авторизован на сессию чата,
у n8n нужен свой Notion integration token). После того как страницу
расшарили с интеграцией и токен передали в n8n, обнаружился реальный баг:
`permission denied for table data_catalog_descriptions` — у роли
`n8n_readonly` не было `SELECT` на эту таблицу (она создана вручную под
`postgres`, а не под `n8n_readonly`, поэтому грант не унаследовался
автоматически). Добавлен в `sql/readonly_role.sql`, после чего вебхук
`docs-refresh` отработал до `success`. Проверено независимо от n8n —
через прямой `notion-fetch` — что старое ручное содержимое страницы
(вступительный абзац) исчезло и заменилось именно тем, что генерирует
воркфлоу: цикл "получить старые блоки → удалить → добавить новые из
живого запроса к БД" отработал по-настоящему, а не только "успешно
завершился" по статусу.
