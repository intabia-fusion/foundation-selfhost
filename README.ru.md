# Интабия Платформа (self-hosted)

[English](README.md) | **Русский**

Разверните Интабия Платформу на своём сервере через `docker compose`.

## Быстрый старт

### Требования

- Операционная система: **Linux или macOS**. Скрипты установки написаны на Bash и требуют Unix-оболочку. На Windows используйте WSL2 (Ubuntu).
- Docker: [инструкция по установке](https://docs.docker.com/engine/install/ubuntu/), затем [шаги после установки](https://docs.docker.com/engine/install/linux-postinstall/)
- Nginx (обратный прокси)
- Node.js (только для утилиты импорта бэкапов Huly, `import-backup.mjs`)

### Установка

```bash
git clone https://github.com/intabia-fusion/platform-selfhost.git
cd platform-selfhost
./setup.sh
```

Скрипт установки:
- получит последнюю версию платформы с GitHub;
- спросит адрес хоста, порт, SSL, LiveKit и настройки томов;
- сгенерирует `config/platform.conf` со всеми настройками;
- сгенерирует секреты (только при первом запуске, повторно не перезаписываются);
- создаст конфигурацию nginx.

### Запуск сервисов

```bash
./up.sh
```

> [!NOTE]
> По умолчанию платформа слушает **порт 80** и доступна напрямую по адресу
> `http://<host>`. Если задать другой `--port` (например, `8080`), перед ней
> нужно поставить собственный обратный прокси - встроенный nginx пробрасывает
> выбранный порт хоста прямо в контейнер, порт 80 больше никто не обслуживает.

### Остановка сервисов

```bash
./down.sh          # Остановить сервисы (данные сохраняются)
./cleanup.sh       # Остановить сервисы (данные сохраняются)
./cleanup.sh --all # Полный сброс: удалить конфиг, секреты и данные
```

## Опции установки

```
./setup.sh [OPTIONS]

  --silent              Неинтерактивный режим (значения по умолчанию или переданные)
  --dev                 Режим разработки (localhost, LiveKit с devkey, без SSL)
  --host <address>      Адрес хоста (например, localhost или platform.example.com)
  --port <port>         HTTP-порт (по умолчанию: 80)
  --ssl                 Включить SSL/HTTPS
  --ssl-cert <path>     Путь к SSL-сертификату (fullchain.pem), копируется в config/certs/
  --ssl-key <path>      Путь к приватному ключу SSL (privkey.pem), копируется в config/certs/
  --use-livekit         Включить LiveKit для аудио- и видеозвонков
  --livekit-host <url>  URL сервера LiveKit (по умолчанию: ws://<host>/livekit)
  --version <ver>       Версия платформы (например, v0.8.0). Если не задана, берётся последняя с GitHub
  --push-public-key <k> Публичный ключ VAPID для web push
  --push-private-key <k> Приватный ключ VAPID для web push
  --llm-provider <p>    LLM-провайдер AI-бота: openai, gigachat, server, пусто - выключить
  --openai-key <k>      Ключ OpenAI-совместимого API
  --openai-base-url <u> Базовый URL OpenAI-совместимого API (локальные модели: http://host.docker.internal:1234/v1/)
  --openai-model <m>    Название модели (также применяется к моделям пересказа и перевода)
  --stt-provider <p>    Провайдер транскрибации: openai, deepgram, server, пусто - выключить
  --stt-url <url>       OpenAI-совместимый endpoint транскрибации
  --stt-key <k>         Ключ API транскрибации
  --stt-model <m>       Название модели транскрибации
  --reset-volumes       Сбросить пути томов на именованные тома Docker
```

Настройка LLM и транскрибации описана в разделе [AI-бот](#ai-бот).

## Развёртывание через CI/CD

### Сценарий 1: обновление - новая версия с сохранением данных

Используйте при обновлении dev-машин на новую версию платформы без потери данных.

```bash
#!/bin/bash
# CI: обновление devp1.intabia.ru до новой версии
set -e

cd /path/to/platform-selfhost
git pull

./setup.sh --silent \
  --host devp1.intabia.ru \
  --ssl \
  --ssl-cert /etc/letsencrypt/live/devp1.intabia.ru/fullchain.pem \
  --ssl-key /etc/letsencrypt/live/devp1.intabia.ru/privkey.pem \
  --version v0.8.0 \
  --use-livekit

./up.sh --pull --recreate
```

Что происходит:
- конфиг обновляется указанной версией и настройками;
- LiveKit по умолчанию получает адрес `wss://lkit.devp1.intabia.ru` (генерируется из хоста при SSL);
- существующие данные сохраняются (Postgres, Elasticsearch, Redpanda, Minio);
- существующие секреты сохраняются (не перегенерируются, если файлы есть);
- ключи VAPID для web push генерируются автоматически при первом запуске;
- новые образы Docker скачиваются, контейнеры пересоздаются.

### Сценарий 2: чистое развёртывание с нуля

Используйте для новой машины или полного сброса.

```bash
#!/bin/bash
# CI: чистое развёртывание devp1.intabia.ru с нуля
set -e

cd /path/to/platform-selfhost
git pull

# Полная очистка (удаляет конфиг, секреты, данные, образы)
./cleanup.sh --all || true

./setup.sh --silent \
  --host devp1.intabia.ru \
  --ssl \
  --ssl-cert /etc/letsencrypt/live/devp1.intabia.ru/fullchain.pem \
  --ssl-key /etc/letsencrypt/live/devp1.intabia.ru/privkey.pem \
  --version v0.8.0 \
  --use-livekit

./up.sh --pull
```

Что происходит:
- удаляются все существующие конфиги, секреты, данные и ресурсы Docker;
- генерируются новые секреты и ключи VAPID;
- LiveKit по умолчанию получает адрес `wss://lkit.devp1.intabia.ru`;
- создаются пустые базы данных;
- образы скачиваются, сервисы запускаются.

> **Примечание:** замените `devp1` на номер конкретной машины (`devp2`, `devp3` и т.д.). SSL-сертификаты для `devpN.intabia.ru` и `lkit.devpN.intabia.ru` должны быть выпущены заранее.

### Ключевые различия

| | Обновление (сценарий 1) | Чистая установка (сценарий 2) |
|---|---|---|
| Секреты | Сохраняются (файлы есть) | Новые (файлы удалены очисткой) |
| Ключи VAPID | Сохраняются | Новые |
| База данных | Сохраняется | Пустая |
| Образы Docker | Скачиваются при `--pull` | Скачиваются |
| Контейнеры | Пересоздаются при `--recreate` | Создаются |
| Конфиг | Перегенерируется из шаблона | Генерируется с нуля |

> **Примечание:** секреты генерируются только если файлов нет (`config/.platform.secret`, `config/.postgres.secret`, `config/.rp.secret`). Если каталоги с данными существуют, а секреты отсутствуют, setup.sh предупредит о возможном несоответствии.

## Режим разработки

Для локальной разработки на macOS:

```bash
./setup.sh --dev
./up.sh
# В отдельном терминале:
./dev/run-livekit.sh
```

`--dev` влияет только на LiveKit:
- LiveKit запускается локально с `devkey/secret` на порту 7880 (не в Docker);
- dev-конфиги LiveKit копируются в `config/`;
- всё остальное (хост, порт, SSL, тома) настраивается обычным образом через вопросы или флаги.

Установка LiveKit на macOS: `brew install livekit`

## Конфигурация

Вся конфигурация лежит в `config/`:

| Файл | Описание |
|---|---|
| `config/platform.conf` | Основной конфиг (переменные окружения для docker compose) |
| `config/version.txt` | Версия платформы |
| `config/branding.json` | Настройки брендирования |
| `config/region-config.yaml` | Конфигурация регионов |
| `config/nginx.conf` | Конфигурация nginx |
| `config/livekit.yaml` | Конфиг сервера LiveKit (когда включён) |
| `config/livekit-egress-config.yaml` | Конфиг LiveKit Egress (когда включён) |
| `config/certs/` | SSL-сертификаты (`fullchain.pem`, `privkey.pem`) |
| `config/.platform.secret` | Секрет платформы |
| `config/.postgres.secret` | Пароль PostgreSQL |
| `config/.rp.secret` | Пароль администратора Redpanda |
| `config/.admin.secret` | Пароль технического администратора (создаётся при первом импорте бэкапа) |

### Секреты

Секреты генерируются один раз и никогда не перезаписываются. Если нужно перегенерировать:

1. Остановите сервисы: `./down.sh`
2. Удалите нужный файл секрета (например, `rm config/.platform.secret`)
3. Запустите `./setup.sh` снова

> **Внимание:** если удалить `config/.postgres.secret` или `config/.rp.secret` при существующих каталогах с данными, новые секреты не совпадут с сохранёнными паролями. Либо удалите данные (`./cleanup.sh --all`), либо вручную поменяйте пароль внутри работающего сервиса.

## Настройка томов

По умолчанию данные хранятся в подкаталогах `./data/`. В интерактивной установке можно:

- нажать Enter для значений по умолчанию (`./data/<service>`);
- ввести собственный абсолютный путь;
- ввести `none` для именованных томов Docker.

Сбросить все пути на именованные тома Docker:

```bash
./setup.sh --reset-volumes
```

## Nginx

Установка генерирует `config/nginx.conf`. Чтобы активировать конфиг, добавьте символьную ссылку в каталог sites-enabled:

```bash
sudo ln -s $(pwd)/config/nginx.conf /etc/nginx/sites-enabled/platform.conf
sudo nginx -s reload
```

Либо используйте скрипт `nginx.sh` с флагами `--link` и `--reload`.

### Обновление конфигурации nginx

После изменения `HOST_ADDRESS`, `SECURE`, `HTTP_PORT` или `HTTP_BIND` перегенерируйте конфиг:

```bash
./nginx.sh
```

Скрипт поддерживает несколько опций:

- `--ssl-cert <path>` - скопировать SSL-сертификат в `config/certs/fullchain.pem` (для LiveKit) и указать этот путь в конфигурации nginx
- `--ssl-key <path>` - скопировать приватный ключ SSL в `config/certs/privkey.pem` (для LiveKit) и указать этот путь в конфигурации nginx
- `--link` - создать или обновить символьную ссылку `/etc/nginx/sites-enabled/platform.conf`
- `--reload` - выполнить `sudo nginx -s reload` без подтверждения
- `--auto` - то же, что `--link --reload`
- `--recreate` - перегенерировать `nginx.conf` из шаблона

Если переданы `--ssl-cert` и `--ssl-key`, nginx будет ссылаться на исходные файлы сертификатов (например, на пути Let's Encrypt). Файлы также копируются в `config/certs/` для совместимости с LiveKit.

Пример для CI/CD:

```bash
./nginx.sh --ssl-cert /etc/letsencrypt/live/platform-dev1.intabia.ru/fullchain.pem \
           --ssl-key /etc/letsencrypt/live/platform-dev1.intabia.ru/privkey.pem \
           --auto
```

Одной командой обновляется конфигурация, копируются сертификаты (для LiveKit), создаётся ссылка и перезагружается nginx.

## Web Push уведомления

Ключи VAPID для браузерных push-уведомлений **генерируются автоматически** во время `./setup.sh` (через Docker-контейнер с `web-push`). Ручных шагов не требуется.

Ключи сохраняются в `config/platform.conf` и переиспользуются при последующих запусках.

Чтобы указать свои ключи:

```bash
./setup.sh --push-public-key "BEl62i..." --push-private-key "IwMHkf..."
```

Либо отредактируйте `config/platform.conf` напрямую и перезапустите: `./up.sh --recreate`

## Почтовый сервис

Конфигурация по умолчанию включает **Mailpit** для отладки почты:

- **Интерфейс Mailpit**: `http://<host>:8025` (порт настраивается через `MAILPIT_HTTP_PORT` в `config/platform.conf`)
- **SMTP**: порт 1025 (внутренний, для сервисов Интабия Платформы)

Все письма перехватываются и **не доставляются** реальным получателям.

### Production SMTP

Для отправки реальных писем измените окружение `mail_server` в `compose.yml`:

```yaml
mail_server:
  environment:
    - MODE=queue
    - SOURCE=noreply@yourdomain.com
    - SMTP_HOST=smtp.yourdomain.com
    - SMTP_PORT=587
    - SMTP_USERNAME=your_smtp_user
    - SMTP_PASSWORD=your_smtp_password
    - SMTP_TLS_MODE=require
```

### Amazon SES

См. [руководство по настройке AWS SES](https://docs.aws.amazon.com/ses/latest/dg/setting-up.html). Настройка:

```yaml
mail:
  environment:
    - SES_ACCESS_KEY=<key>
    - SES_SECRET_KEY=<secret>
    - SES_REGION=<region>
```

> SMTP и SES нельзя использовать одновременно.

## LiveKit (аудио- и видеозвонки)

### Production

Запустите `./setup.sh` и включите LiveKit по запросу (или используйте `--use-livekit`).

Необходимые порты в файрволе:
- `7880/tcp` - HTTP/WebSocket API LiveKit
- `7881/tcp` - TCP-релей
- `5349/tcp+udp` - TURN поверх TLS
- `3478/tcp+udp` - TURN
- `50000-60000/udp` - передача медиа

SSL-сертификаты копируются в `config/certs/fullchain.pem` и `config/certs/privkey.pem` (при использовании `--ssl-cert` / `--ssl-key`). LiveKit использует эти копии; nginx может ссылаться на исходные пути Let's Encrypt.

### Разработка

См. [режим разработки](#режим-разработки). LiveKit запускается локально, не в Docker.

## Прочие сервисы

### Сервис печати

Уже включён в `compose.yml`. Настройте сервис `front`:

```yaml
front:
  environment:
    - PRINT_URL=http${SECURE:+s}://${HOST_ADDRESS}/_print
```

### AI-бот

Уже включён в `compose.yml`. Состоит из двух независимых частей: LLM (пересказы, перевод) и
endpoint транскрибации (STT) для записей звонков. Обе части работают с любым OpenAI-совместимым
сервером, поэтому локальные модели подходят так же, как облачные.

Настраивается флагами `./setup.sh` либо правкой `config/platform.conf` с последующим `./up.sh --recreate`.

#### LLM

```
LLM_PROVIDER=openai
OPENAI_API_KEY=token
OPENAI_BASE_URL=http://host.docker.internal:1234/v1/
OPENAI_MODEL=openai/gpt-oss-20b
OPENAI_SUMMARY_MODEL=openai/gpt-oss-20b
OPENAI_TRANSLATE_MODEL=openai/gpt-oss-20b
```

Допустимые значения `LLM_PROVIDER`:

| Значение | Смысл |
|---|---|
| `openai` | Любой OpenAI-совместимый endpoint - сам OpenAI, LM Studio, Ollama, vLLM, llama.cpp |
| `gigachat` | GigaChat (задайте `GIGACHAT_CREDENTIALS` в сервисе `aibot`) |
| `server` | Передавать запросы отдельно развёрнутым клиентам ai-bot |
| пусто | Функции LLM отключены |

Для локального сервера моделей, запущенного на хосте Docker, используйте
`http://host.docker.internal:<port>/v1/` (`localhost` внутри контейнера указывает на сам контейнер,
а не на хост).

Пример с облачным OpenAI:

```bash
./setup.sh --silent \
  --llm-provider openai \
  --openai-key sk-... \
  --openai-base-url https://api.openai.com/v1/ \
  --openai-model gpt-4o-mini
```

Пример с локальным LM Studio:

```bash
./setup.sh --silent \
  --llm-provider openai \
  --openai-base-url http://host.docker.internal:1234/v1/ \
  --openai-model openai/gpt-oss-20b
```

#### Транскрибация (STT)

```
STT_PROVIDER=openai
STT_URL=http://host.docker.internal:9007
STT_API_KEY=key
STT_MODEL=
```

`STT_PROVIDER` принимает `openai` (любой OpenAI-совместимый endpoint `/v1/audio/transcriptions`),
`deepgram`, `server` или пустое значение для отключения транскрибации.

Сервер транскрибации **не входит** в `compose.yml` - запускайте его сами: обычно он требует GPU
и имеет собственный жизненный цикл. Готовый вариант с поддержкой русского языка - `oaitt`:

```bash
docker run -d --name oaitt --restart unless-stopped \
  -p 9007:9007 \
  -e PORT=9007 \
  -e ASR_ENGINE=gigaam \
  -e DEVICE=cpu \
  -e GIGAAM_MODEL=v3_e2e_ctc \
  intabiafusion/oaitt:v1.0.0
```

> Образ `oaitt` опубликован только для `linux/amd64`; на Apple Silicon добавьте `--platform linux/amd64`
> (работает через эмуляцию и медленно). На хосте с GPU используйте `DEVICE=cuda`.

Затем укажите его платформе:

```bash
./setup.sh --silent --stt-provider openai --stt-url http://host.docker.internal:9007
```

Если сервер транскрибации работает на другой машине, укажите её адрес
(например, `--stt-url http://asr.internal:9007`).

### Google Calendar

См. [руководство по настройке Gmail](guides/gmail-configuration.md).

### OpenID Connect (OIDC)

Задайте в окружении сервиса `account`:
- `OPENID_CLIENT_ID`
- `OPENID_CLIENT_SECRET`
- `OPENID_ISSUER`

Redirect URI: `http${SECURE:+s}://${HOST_ADDRESS}/_accounts/auth/openid/callback`

### GitHub OAuth

Задайте в сервисе `account`:
- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`

Redirect URI: `http${SECURE:+s}://${HOST_ADDRESS}/_account/auth/github/callback`

### Отключение регистрации

Задайте `DISABLE_SIGNUP=true` в сервисах `account` и `front`.

## Миграция из облака Huly

Рабочее пространство из облака Huly можно перенести в self-hosted инсталляцию:
скачать его бэкап и восстановить локально.

Проще всего использовать интерактивный мастер:

```bash
./import-from-huly.sh
```

Он последовательно спросит всего две вещи:

1. **URL бэкапа** и **токен** - оба копируются из рабочего пространства Huly в разделе
   `Settings -> Backup -> Backup Files` (кнопки `Copy to clipboard`).
2. **Название рабочего пространства** - любое читаемое имя для нового локального пространства.

Пользователей создавать **не нужно**. Исходные пользователи из бэкапа воссоздаются
автоматически и привязываются к рабочему пространству.

> [!NOTE]
> Пользователи входят по email. В демо-конфигурации код входа (OTP) перехватывает
> **Mailpit** по адресу `http://<host>:8025`. Для production нужно настроить реальный
> SMTP-сервер (см. [Production SMTP](#production-smtp)), чтобы письма с кодом доходили.
> Технический администратор (`admin@platform.local`) создаётся для инициализации
> рабочего пространства; его случайный пароль сохраняется в `config/.admin.secret`.

Загрузки кэшируются в `backups/<huly-workspace-uuid>/` и переиспользуются при повторном запуске.
Крупные медиа-файлы также скачиваются и загружаются в локальный datalake.

Ручные шаги, ограничения по размеру и решение проблем описаны в руководстве по импорту
([English](guides/backup-import.en.md) / [Русский](guides/backup-import.ru.md)).

## Полезные команды

```bash
./up.sh                    # Запустить сервисы
./up.sh --pull             # Скачать свежие образы и запустить
./up.sh --recreate         # Пересоздать контейнеры
./up.sh --pull --recreate  # Скачать + пересоздать (для обновлений)
./down.sh                  # Остановить сервисы
./cleanup.sh               # Остановить сервисы
./cleanup.sh --all         # Полный сброс
./set-version.sh v0.8.0    # Сменить версию платформы
./nginx.sh                 # Перегенерировать конфиг nginx
```
