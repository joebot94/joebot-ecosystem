#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT_DIR/.run"

mkdir -p "$RUN_DIR"

services=(
  "nexus|$ROOT_DIR/nexus|python3 -u main.py"
  "dirtymixer|$ROOT_DIR/DirtyMixerApp|swift run"
  "glitch_catalog|$ROOT_DIR/GlitchCatalogSwift|swift run"
  "observatory|$ROOT_DIR/Observatory|swift run"
)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/joebot-stack.sh up
  ./scripts/joebot-stack.sh down
  ./scripts/joebot-stack.sh status
  ./scripts/joebot-stack.sh logs [service]

Services:
  nexus, dirtymixer, glitch_catalog, observatory
EOF
}

pid_file() {
  echo "$RUN_DIR/$1.pid"
}

log_file() {
  echo "$RUN_DIR/$1.log"
}

is_running() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

start_one() {
  local name="$1"
  local cwd="$2"
  local cmd="$3"
  local pf
  pf="$(pid_file "$name")"

  if [[ -f "$pf" ]]; then
    local existing_pid
    existing_pid="$(cat "$pf")"
    if is_running "$existing_pid"; then
      echo "$name already running (pid $existing_pid)"
      return
    fi
    rm -f "$pf"
  fi

  nohup bash -lc "cd '$cwd' && $cmd" >"$(log_file "$name")" 2>&1 &
  local new_pid=$!
  echo "$new_pid" >"$pf"
  echo "started $name (pid $new_pid)"
}

stop_one() {
  local name="$1"
  local pf
  pf="$(pid_file "$name")"

  if [[ ! -f "$pf" ]]; then
    echo "$name not running (no pid file)"
    return
  fi

  local pid
  pid="$(cat "$pf")"
  if is_running "$pid"; then
    kill "$pid" 2>/dev/null || true
    sleep 0.3
    if is_running "$pid"; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    echo "stopped $name (pid $pid)"
  else
    echo "$name pid file existed but process is not running"
  fi
  rm -f "$pf"
}

status_one() {
  local name="$1"
  local pf
  pf="$(pid_file "$name")"

  if [[ ! -f "$pf" ]]; then
    echo "$name: stopped"
    return
  fi

  local pid
  pid="$(cat "$pf")"
  if is_running "$pid"; then
    echo "$name: running (pid $pid)"
  else
    echo "$name: stale pid file (pid $pid)"
  fi
}

cmd="${1:-}"
case "$cmd" in
  up)
    for entry in "${services[@]}"; do
      IFS="|" read -r name cwd run_cmd <<<"$entry"
      start_one "$name" "$cwd" "$run_cmd"
    done
    echo
    echo "Stack starting. Check status with:"
    echo "  ./scripts/joebot-stack.sh status"
    echo "Logs are in: $RUN_DIR"
    ;;
  down)
    for entry in "${services[@]}"; do
      IFS="|" read -r name _ _ <<<"$entry"
      stop_one "$name"
    done
    ;;
  status)
    for entry in "${services[@]}"; do
      IFS="|" read -r name _ _ <<<"$entry"
      status_one "$name"
    done
    ;;
  logs)
    service="${2:-all}"
    if [[ "$service" == "all" ]]; then
      for entry in "${services[@]}"; do
        IFS="|" read -r name _ _ <<<"$entry"
        echo "===== $name ====="
        tail -n 40 "$(log_file "$name")" 2>/dev/null || echo "(no log yet)"
      done
    else
      tail -n 120 "$(log_file "$service")"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
