# multipass

L4 SNI-роутер на **HAProxy** для ноды с **Remnawave / Xray**.

Один публичный вход `:443/tcp`, без TLS-терминации: по SNI трафик уходит на Unix-сокеты.

**Образ:** [`ghcr.io/raaad1on/multipass`](https://github.com/raaad1on/multipass/pkgs/container/multipass)

## Роутинг

| SNI | Backend | Транспорт |
|-----|---------|-----------|
| `xhttp-${NODE_HOST}` | `/dev/shm/nginx/xhttp.sock` | xHTTP + Reality |
| `grpc-${NODE_HOST}` | `/dev/shm/nginx/grpc.sock` | gRPC + TLS |
| всё остальное | `/dev/shm/nginx/reality.sock` | RAW + Reality (+ Vision) / заглушка |

```text
Client ──► multipass (HAProxy) :443
              ├─ xhttp-de02.example.com ──► xhttp.sock
              ├─ grpc-de02.example.com  ──► grpc.sock
              └─ *                        ──► reality.sock
```

## Имена хостов

`NODE_HOST` — третий уровень домена:

- `de.example.com` — код локации
- `de02.example.com` — код локации + номер

Транспортные SNI собираются автоматически:

- `xhttp-${NODE_HOST}` → `xhttp-de02.example.com`
- `grpc-${NODE_HOST}` → `grpc-de02.example.com`

Wildcard-сертификат на зону покрывает любые такие имена (нужен для gRPC + TLS).

## Быстрый старт

1. Подставьте свой хост ноды в `docker-compose.yml`:

```yaml
environment:
  NODE_HOST: de02.example.com
```

2. **Сначала** запустите multipass (создаёт `/dev/shm/nginx` и чистит старые `*.sock` / `*.sock.lock`), **потом** Remnawave/Xray:

```bash
docker compose pull
docker compose up -d
docker compose logs -f
```

Если Remnawave уже запущен и падает на сокетах — перезапустите его после multipass:

```bash
docker compose up -d          # multipass
docker restart remnanode      # или ваш контейнер Xray
```

Вручную на хосте (если нужно до всего):

```bash
mkdir -p /dev/shm/nginx
chmod 755 /dev/shm/nginx
```

Или одной командой без compose:

```bash
docker run -d --name multipass --network host --restart unless-stopped \
  -v /dev/shm/nginx:/dev/shm/nginx \
  --ulimit nofile=200000:200000 \
  -e NODE_HOST=de02.example.com \
  ghcr.io/raaad1on/multipass:latest
```

> Первый pull из GHCR для публичного пакета обычно работает без логина. Если GitHub потребует auth: `echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin`.

Проверка SNI (с сервера):

```bash
echo | openssl s_client -connect 127.0.0.1:443 -servername xhttp-de02.example.com -brief
echo | openssl s_client -connect 127.0.0.1:443 -servername grpc-de02.example.com -brief
echo | openssl s_client -connect 127.0.0.1:443 -servername de02.example.com -brief
```

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `NODE_HOST` | *обязательно* | Хост ноды (`de.example.com` / `de02.example.com`) |
| `LISTEN_PORT` | `443` | Порт bind HAProxy |
| `XHTTP_SNI` | `xhttp-${NODE_HOST}` | SNI для xHTTP |
| `GRPC_SNI` | `grpc-${NODE_HOST}` | SNI для gRPC |
| `XHTTP_SOCK_PATH` | `/dev/shm/nginx/xhttp.sock` | Unix-сокет xHTTP |
| `GRPC_SOCK_PATH` | `/dev/shm/nginx/grpc.sock` | Unix-сокет gRPC |
| `REALITY_SOCK_PATH` | `/dev/shm/nginx/reality.sock` | Unix-сокет Reality / Vision |
| `SOCK_DIR_MODE` | `755` | Права на каталог сокетов |

## Контракт inbound'ов (Remnawave / Xray)

Xray **сам** слушает Unix-сокеты и создаёт `*.sock` + `*.sock.lock`.  
multipass готовит каталог `/dev/shm/nginx` и убирает устаревшие файлы после крэша.

HAProxy подключается к:

- `reality.sock` — RAW + Reality (+ Vision) / fallback
- `xhttp.sock` — xHTTP + Reality
- `grpc.sock` — gRPC + TLS (`alpn`: `h2` первым), wildcard-сертификат на зону

Ошибка вида `open .../reality.sock.lock: no such file or directory` значит, что каталог ещё не создан — поднимите multipass раньше Xray.

## CI/CD

При пуше в `main` GitHub Actions собирает multi-arch образ (`linux/amd64`, `linux/arm64`) и публикует в GHCR:

- `ghcr.io/raaad1on/multipass:latest`
- `ghcr.io/raaad1on/multipass:<git-sha>`
- при теге `vX.Y.Z` — semver-теги

Workflow: [`.github/workflows/docker.yml`](.github/workflows/docker.yml)

Локальная сборка:

```bash
docker build -t multipass:local .
```

## Важно

- Стартуйте **multipass → затем Remnawave/Xray**, иначе Xray не сможет создать `*.sock.lock`.
- Каталог `/dev/shm/nginx` монтируется в контейнер; entrypoint делает `mkdir -p` и чистит stale sockets.
- TLS не терминируется в HAProxy (включая gRPC) — только passthrough.
- PROXY protocol не используется.
- `ulimit nofile` для контейнера: `200000`.

## Состав репозитория

| Файл | Описание |
|------|----------|
| `Dockerfile` | Образ на базе `haproxy:3.0-alpine` |
| `docker-compose.yml` | Пример деплоя с `ghcr.io/raaad1on/multipass` |
| `haproxy.cfg` | Шаблон конфига (подстановка env при старте) |
| `docker-entrypoint.sh` | Сборка SNI + рендер конфига + запуск HAProxy |
| `.github/workflows/docker.yml` | CI/CD сборки и публикации образа |
