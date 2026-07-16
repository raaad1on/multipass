# multipass

L4 SNI-роутер на **HAProxy** для ноды с **Remnawave / Xray**.

Один публичный вход `:443/tcp`, без TLS-терминации. **Unix-сокеты создаёт и слушает multipass**; дальше `socat` форвардит на TCP-порты Xray (Xray сам сокеты не создаёт).

**Образ:** [`ghcr.io/raaad1on/multipass`](https://github.com/raaad1on/multipass/pkgs/container/multipass)

## Архитектура

```text
Client ──► HAProxy :443 (SNI)
              ├─ xhttp-${NODE_HOST} ──► /dev/shm/nginx/xhttp.sock  ──socat──► 127.0.0.1:10444 (Xray xHTTP)
              ├─ grpc-${NODE_HOST}  ──► /dev/shm/nginx/grpc.sock   ──socat──► 127.0.0.1:10445 (Xray gRPC)
              └─ *                  ──► /dev/shm/nginx/reality.sock──socat──► 127.0.0.1:10443 (Xray Reality)
```

## Роутинг

| SNI | Unix-сокет (multipass) | Upstream Xray (TCP) |
|-----|------------------------|---------------------|
| `xhttp-${NODE_HOST}` | `xhttp.sock` | `XHTTP_UPSTREAM` |
| `grpc-${NODE_HOST}` | `grpc.sock` | `GRPC_UPSTREAM` |
| всё остальное | `reality.sock` | `REALITY_UPSTREAM` |

## Имена хостов

`NODE_HOST` — третий уровень домена:

- `de.example.com` — код локации
- `de02.example.com` — код локации + номер

Транспортные SNI собираются автоматически:

- `xhttp-${NODE_HOST}` → `xhttp-de02.example.com`
- `grpc-${NODE_HOST}` → `grpc-de02.example.com`

Wildcard-сертификат на зону покрывает любые такие имена (нужен для gRPC + TLS).

## Быстрый старт

1. В Remnawave поднимите 3 inbound'а на TCP `127.0.0.1` (порты ниже).
2. Подставьте хост ноды и при необходимости порты в `docker-compose.yml`:

```yaml
environment:
  NODE_HOST: de02.example.com
  REALITY_UPSTREAM: 127.0.0.1:10443
  XHTTP_UPSTREAM: 127.0.0.1:10444
  GRPC_UPSTREAM: 127.0.0.1:10445
```

3. Запуск:

```bash
docker compose pull
docker compose up -d
docker compose logs -f
```

Или без compose:

```bash
docker run -d --name multipass --network host --restart unless-stopped \
  -v /dev/shm/nginx:/dev/shm/nginx \
  --ulimit nofile=200000:200000 \
  -e NODE_HOST=de02.example.com \
  -e REALITY_UPSTREAM=127.0.0.1:10443 \
  -e XHTTP_UPSTREAM=127.0.0.1:10444 \
  -e GRPC_UPSTREAM=127.0.0.1:10445 \
  ghcr.io/raaad1on/multipass:latest
```

Проверка сокетов:

```bash
ls -l /dev/shm/nginx/
```

Проверка SNI:

```bash
echo | openssl s_client -connect 127.0.0.1:443 -servername xhttp-de02.example.com -brief
echo | openssl s_client -connect 127.0.0.1:443 -servername grpc-de02.example.com -brief
echo | openssl s_client -connect 127.0.0.1:443 -servername de02.example.com -brief
```

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `NODE_HOST` | *обязательно* | Хост ноды |
| `LISTEN_PORT` | `443` | Порт bind HAProxy |
| `XHTTP_SNI` | `xhttp-${NODE_HOST}` | SNI для xHTTP |
| `GRPC_SNI` | `grpc-${NODE_HOST}` | SNI для gRPC |
| `XHTTP_SOCK_PATH` | `/dev/shm/nginx/xhttp.sock` | Unix-сокет xHTTP |
| `GRPC_SOCK_PATH` | `/dev/shm/nginx/grpc.sock` | Unix-сокет gRPC |
| `REALITY_SOCK_PATH` | `/dev/shm/nginx/reality.sock` | Unix-сокет Reality |
| `REALITY_UPSTREAM` | `127.0.0.1:10443` | TCP Xray Reality / Vision |
| `XHTTP_UPSTREAM` | `127.0.0.1:10444` | TCP Xray xHTTP |
| `GRPC_UPSTREAM` | `127.0.0.1:10445` | TCP Xray gRPC |
| `SOCK_MODE` | `666` | mode Unix-сокетов |

## Контракт Remnawave / Xray

Xray слушает **только TCP** на `127.0.0.1`. Сокеты в `/dev/shm/nginx/` создаёт multipass.

### 1. Reality / Vision — `REALITY_UPSTREAM` (default `127.0.0.1:10443`)

- `listen`: `127.0.0.1`, порт из `REALITY_UPSTREAM`
- `network`: `raw`, `security`: `reality`
- клиенты Vision: `flow: xtls-rprx-vision`

### 2. xHTTP — `XHTTP_UPSTREAM` (default `127.0.0.1:10444`)

- `network`: `xhttp`, `security`: `reality`
- без Vision flow
- `realitySettings.serverNames`: `[XHTTP_SNI]`

### 3. gRPC — `GRPC_UPSTREAM` (default `127.0.0.1:10445`)

- `network`: `grpc`, `security`: `tls`
- `tlsSettings.alpn`: `["h2", "http/1.1"]` — **`h2` первым**
- wildcard-сертификат на зону

## CI/CD

При пуше в `main` GitHub Actions собирает multi-arch образ (`linux/amd64`, `linux/arm64`) и публикует в GHCR:

- `ghcr.io/raaad1on/multipass:latest`
- `ghcr.io/raaad1on/multipass:<git-sha>`
- при теге `vX.Y.Z` — semver-теги

## Важно

- `network_mode: host` — чтобы HAProxy/socat видели Xray на `127.0.0.1`.
- TLS не терминируется в HAProxy — только passthrough.
- PROXY protocol не используется.
- `ulimit nofile`: `200000`.
