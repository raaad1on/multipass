# multipass (redirect)

L4 SNI-роутер на **HAProxy**: один публичный `:443/tcp`, без TLS-терминации. По SNI трафик уходит на **внешний IP:port** (не на Unix-сокеты).

**Образ:** [`ghcr.io/raaad1on/multipass:redirect`](https://github.com/raaad1on/multipass/pkgs/container/multipass)

> Ветка `redirect`. Классический режим с UDS для Remnawave/Xray — в `main` (`:latest`).

## Роутинг

В `ROUTES` задаются зоны (`*.zone`) и при необходимости точные SNI.  
Для каждой зоны правило `xhttp-*` создаётся автоматически на тот же IP и `XHTTP_PORT` (по умолчанию `8443`).

| SNI | Backend |
|-----|---------|
| `xhttp-*.example.com` | `<ip>:XHTTP_PORT` (авто из зоны) |
| `special.example.com` | exact host из `ROUTES` (без авто-xhttp) |
| `*.example.com` | `<ip>:<port>` из `ROUTES` |
| неизвестный SNI | reject |

Порядок матча: `xhttp-*` → exact → `*.zone`.

```text
Client ──► multipass (HAProxy) :443
              ├─ xhttp-de.example.com     ──► 1.1.1.1:8443
              ├─ special.example.com      ──► 2.2.2.2:443
              ├─ de.example.com           ──► 1.1.1.1:443
              └─ unknown                  ──► reject
```

Пример `ROUTES`:

```text
special.example.com=2.2.2.2:443
*.example.com=1.1.1.1:443
*.example2.com=3.3.3.3:443
```

## Быстрый старт

```bash
mkdir -p /opt/multipass && cd /opt/multipass

curl -fsSL -o docker-compose.yml \
  https://raw.githubusercontent.com/raaad1on/multipass/redirect/docker-compose.yml.dist

# edit ROUTES
nano docker-compose.yml

docker compose pull
docker compose up -d
```

### Проверка

```bash
docker compose logs -f

echo | openssl s_client -connect 127.0.0.1:443 -servername xhttp-de.example.com -brief
echo | openssl s_client -connect 127.0.0.1:443 -servername de.example.com -brief
```

> Первый pull из GHCR для публичного пакета обычно работает без логина. Если GitHub потребует auth: `echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin`.

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `ROUTES` | *обязательно* | `*.zone.tld=host:port` и/или `exact.host=host:port` (строки или `;`) |
| `LISTEN_PORT` | `443` | Порт bind HAProxy |
| `XHTTP_PORT` | `8443` | Порт для авто-правил `xhttp-*.zone` (тот же host) |

## CI/CD

Пуш в `redirect` публикует:

- `ghcr.io/raaad1on/multipass:redirect`
- `ghcr.io/raaad1on/multipass:<git-sha>`

Пуш в `main` по-прежнему даёт `:latest` (UDS-режим).

Локальная сборка:

```bash
docker build -t multipass:redirect .
```

## Важно

- TLS не терминируется — только TCP passthrough по SNI.
- PROXY protocol не используется.
- Неизвестный SNI отклоняется (не открытый прокси).
- Логи: без per-connection tcplog; Docker `max-size: 10m`.
- `ulimit nofile` для контейнера: `1048576`.

## Состав репозитория

| Файл | Описание |
|------|----------|
| `Dockerfile` | Образ на базе `haproxy:3.0-alpine` |
| `docker-compose.yml.dist` | Шаблон для деплоя |
| `docker-entrypoint.sh` | Парсинг `ROUTES` + генерация HAProxy cfg + запуск |
| `.github/workflows/docker.yml` | CI/CD сборки и публикации образа |
