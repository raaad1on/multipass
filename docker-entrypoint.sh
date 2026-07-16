#!/bin/sh
set -eu

# HAProxy SNI-routes to Unix sockets under /dev/shm/nginx/.
# Ensure socket directory exists; listeners on those paths are external to this entrypoint.

: "${NODE_HOST:?NODE_HOST is required (e.g. de.example.com or de02.example.com)}"
: "${LISTEN_PORT:=443}"
: "${XHTTP_SOCK_PATH:=/dev/shm/nginx/xhttp.sock}"
: "${GRPC_SOCK_PATH:=/dev/shm/nginx/grpc.sock}"
: "${REALITY_SOCK_PATH:=/dev/shm/nginx/reality.sock}"

: "${XHTTP_SNI:=xhttp-${NODE_HOST}}"
: "${GRPC_SNI:=grpc-${NODE_HOST}}"

TEMPLATE="/usr/local/etc/haproxy/haproxy.cfg.template"
RENDERED="/tmp/haproxy.cfg"

mkdir -p "$(dirname "$XHTTP_SOCK_PATH")" \
         "$(dirname "$GRPC_SOCK_PATH")" \
         "$(dirname "$REALITY_SOCK_PATH")"

sed \
  -e "s|\${LISTEN_PORT}|${LISTEN_PORT}|g" \
  -e "s|\${XHTTP_SNI}|${XHTTP_SNI}|g" \
  -e "s|\${GRPC_SNI}|${GRPC_SNI}|g" \
  -e "s|\${XHTTP_SOCK_PATH}|${XHTTP_SOCK_PATH}|g" \
  -e "s|\${GRPC_SOCK_PATH}|${GRPC_SOCK_PATH}|g" \
  -e "s|\${REALITY_SOCK_PATH}|${REALITY_SOCK_PATH}|g" \
  "$TEMPLATE" > "$RENDERED"

exec haproxy -f "$RENDERED" -db "$@"
