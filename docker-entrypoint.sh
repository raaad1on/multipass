#!/bin/sh
set -eu

# HAProxy SNI-routes to Unix sockets under /dev/shm/nginx/.
# Xray listens on those sockets and creates *.sock + *.sock.lock itself.
# multipass only prepares the directory and clears stale socket/lock files.

: "${NODE_HOST:?NODE_HOST is required (e.g. de.example.com or de02.example.com)}"
: "${LISTEN_PORT:=443}"
: "${XHTTP_SOCK_PATH:=/dev/shm/nginx/xhttp.sock}"
: "${GRPC_SOCK_PATH:=/dev/shm/nginx/grpc.sock}"
: "${REALITY_SOCK_PATH:=/dev/shm/nginx/reality.sock}"
: "${SOCK_DIR_MODE:=755}"

: "${XHTTP_SNI:=xhttp-${NODE_HOST}}"
: "${GRPC_SNI:=grpc-${NODE_HOST}}"

TEMPLATE="/usr/local/etc/haproxy/haproxy.cfg.template"
RENDERED="/tmp/haproxy.cfg"

prepare_sock_dir() {
  dir="$1"
  mkdir -p "$dir"
  chmod "$SOCK_DIR_MODE" "$dir"
}

# Remove broken leftovers only. Never unlink a live socket while Xray is listening.
clear_stale_sock() {
  path="$1"
  if [ -e "$path" ] && [ ! -S "$path" ]; then
    rm -f "$path"
  fi
  if [ -e "${path}.lock" ] && [ ! -S "$path" ]; then
    rm -f "${path}.lock"
  fi
}

prepare_sock_dir "$(dirname "$XHTTP_SOCK_PATH")"
prepare_sock_dir "$(dirname "$GRPC_SOCK_PATH")"
prepare_sock_dir "$(dirname "$REALITY_SOCK_PATH")"

clear_stale_sock "$XHTTP_SOCK_PATH"
clear_stale_sock "$GRPC_SOCK_PATH"
clear_stale_sock "$REALITY_SOCK_PATH"

sed \
  -e "s|\${LISTEN_PORT}|${LISTEN_PORT}|g" \
  -e "s|\${XHTTP_SNI}|${XHTTP_SNI}|g" \
  -e "s|\${GRPC_SNI}|${GRPC_SNI}|g" \
  -e "s|\${XHTTP_SOCK_PATH}|${XHTTP_SOCK_PATH}|g" \
  -e "s|\${GRPC_SOCK_PATH}|${GRPC_SOCK_PATH}|g" \
  -e "s|\${REALITY_SOCK_PATH}|${REALITY_SOCK_PATH}|g" \
  "$TEMPLATE" > "$RENDERED"

exec haproxy -f "$RENDERED" -db "$@"
