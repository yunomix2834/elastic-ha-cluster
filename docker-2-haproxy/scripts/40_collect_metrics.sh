#!/usr/bin/env bash
set -euo pipefail

ES_URL="${ES_URL:-https://haproxy-1:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"
CA_CERT="${CA_CERT:-/certs/ca/ca.crt}"
OUT_DIR="${OUT_DIR:-/tmp/es-metrics}"

mkdir -p "$OUT_DIR"
ts="$(date +%F_%H%M%S)"

req() {
  local path="$1"
  local out="$2"
  curl -sS --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
    "$ES_URL$path" > "$out"
  echo "[metrics] wrote $out"
}

req "/_cluster/health"            "$OUT_DIR/${ts}_health.json"
req "/_cat/nodes?v&h=name,ip,role,heap.percent,ram.percent,cpu,load_1m,master" "$OUT_DIR/${ts}_nodes.txt"
req "/_nodes/stats/jvm,process,os,thread_pool,fs,indices" "$OUT_DIR/${ts}_nodes_stats.json"
req "/_stats?pretty"              "$OUT_DIR/${ts}_indices_stats.json"
req "/_cat/thread_pool?v"         "$OUT_DIR/${ts}_thread_pool.txt"
req "/_cat/shards?v"              "$OUT_DIR/${ts}_shards.txt"

echo "[metrics] all done -> $OUT_DIR"