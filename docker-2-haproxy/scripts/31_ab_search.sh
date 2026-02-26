#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-haproxy-1}"
PORT="${PORT:-9200}"
INDEX="${INDEX:-bench_docs}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"

N="${N:-20000}"
C="${C:-200}"
KEEPALIVE="${KEEPALIVE:-true}"
TIMEOUT="${TIMEOUT:-120}"     # NEW
VERBOSE="${VERBOSE:-0}"       # NEW (0/1)

auth="$(printf "%s:%s" "$ES_USER" "$ES_PASS" | base64 -w0)"

cat > /tmp/search.json <<'JSON'
{"size":10,"track_total_hits":false,"query":{"match":{"msg":"a"}}}
JSON

ka_flag=""
[[ "$KEEPALIVE" == "true" ]] && ka_flag="-k"

v_flag=""
[[ "$VERBOSE" == "1" ]] && v_flag="-v 2"

echo "[ab] N=$N C=$C timeout=${TIMEOUT}s keepalive=$KEEPALIVE target=https://$HOST:$PORT/$INDEX/_search"

ab $v_flag $ka_flag -s "$TIMEOUT" -n "$N" -c "$C" \
  -T "application/json" \
  -H "Authorization: Basic $auth" \
  -p /tmp/search.json \
  "https://$HOST:$PORT/$INDEX/_search"