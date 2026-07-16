#!/bin/sh
set -eu

# multipass owns Unix sockets under /dev/shm/nginx/:
#   HAProxy (:LISTEN_PORT) SNI-routes to the sockets;
#   socat listens on each socket and forwards to Xray TCP upstreams.
# Xray/Remnawave must listen on the TCP upstreams (not on the Unix sockets).

: "${NODE_HOST:?NODE_HOST is required (e.g. de.example.com or de02.example.com)}"
: "${LISTEN_PORT:=443}"

: "${XHTTP_SOCK_PATH:=/dev/shm/nginx/xhttp.sock}"
: "${GRPC_SOCK_PATH:=/dev/shm/nginx/grpc.sock}"
: "${REALITY_SOCK_PATH:=/dev/shm/nginx/reality.sock}"

: "${XHTTP_UPSTREAM:=127.0.0.1:10444}"
: "${GRPC_UPSTREAM:=127.0.0.1:10445}"
: "${REALITY_UPSTREAM:=127.0.0.1:10443}"

: "${XHTTP_SNI:=xhttp-${NODE_HOST}}"
: "${GRPC_SNI:=grpc-${NODE_HOST}}"

: "${SOCK_MODE:=666}"

TEMPLATE="/usr/local/etc/haproxy/haproxy.cfg.template"
RENDERED="/tmp/haproxy.cfg"
PIDS=""

log() {
  printf '%s\n' "$*"
}

cleanup() {
  code=$?
  if [ -n "$PIDS" ]; then
    # shellcheck disable=SC2086
    kill $PIDS 2>/dev/null || true
    # shellcheck disable=SC2086
    wait $PIDS 2>/dev/null || true
  fi
  exit "$code"
}

trap cleanup INT TERM EXIT

start_bridge() {
  sock_path="$1"
  upstream="$2"
  name="$3"
  sock_dir=$(dirname "$sock_path")

  mkdir -p "$sock_dir"
  rm -f "$sock_path"

  # unlink-early: create listening socket immediately; mode for peer access on /dev/shm
  socat \
    "UNIX-LISTEN:${sock_path},fork,reuseaddr,unlink-early,mode=${SOCK_MODE}" \
    "TCP:${upstream}" &
  pid=$!
  PIDS="$PIDS $pid"
  log "bridge ${name}: ${sock_path} -> ${upstream} (pid ${pid})"
}

wait_socket() {
  sock_path="$1"
  name="$2"
  i=0
  while [ "$i" -lt 20 ]; do
    if [ -S "$sock_path" ]; then
      log "socket ready: ${name} (${sock_path})"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  log "ERROR: socket not ready: ${name} (${sock_path})"
  return 1
}

sed \
  -e "s|\${LISTEN_PORT}|${LISTEN_PORT}|g" \
  -e "s|\${XHTTP_SNI}|${XHTTP_SNI}|g" \
  -e "s|\${GRPC_SNI}|${GRPC_SNI}|g" \
  -e "s|\${XHTTP_SOCK_PATH}|${XHTTP_SOCK_PATH}|g" \
  -e "s|\${GRPC_SOCK_PATH}|${GRPC_SOCK_PATH}|g" \
  -e "s|\${REALITY_SOCK_PATH}|${REALITY_SOCK_PATH}|g" \
  "$TEMPLATE" > "$RENDERED"

start_bridge "$XHTTP_SOCK_PATH" "$XHTTP_UPSTREAM" "xhttp"
start_bridge "$GRPC_SOCK_PATH" "$GRPC_UPSTREAM" "grpc"
start_bridge "$REALITY_SOCK_PATH" "$REALITY_UPSTREAM" "reality"

wait_socket "$XHTTP_SOCK_PATH" "xhttp"
wait_socket "$GRPC_SOCK_PATH" "grpc"
wait_socket "$REALITY_SOCK_PATH" "reality"

log "SNI: xhttp=${XHTTP_SNI} grpc=${GRPC_SNI} default=reality"
log "starting haproxy on :${LISTEN_PORT}"

haproxy -f "$RENDERED" -db "$@" &
PIDS="$PIDS $!"

# Exit if any child dies (bridge or haproxy).
while true; do
  # shellcheck disable=SC2086
  for pid in $PIDS; do
    if ! kill -0 "$pid" 2>/dev/null; then
      log "process ${pid} exited — shutting down"
      exit 1
    fi
  done
  sleep 1
done
