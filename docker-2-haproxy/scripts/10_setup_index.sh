#!/usr/bin/env bash
set -euo pipefail

ES_URL="${ES_URL:-https://haproxy-1:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"
CA_CERT="${CA_CERT:-/certs/ca/ca.crt}"

INDEX="${INDEX:-bench_docs}"
SHARDS="${SHARDS:-3}"
REPLICAS="${REPLICAS:-1}"

echo "[setup] create index=$INDEX shards=$SHARDS replicas=$REPLICAS"

curl -sS --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
  -X DELETE "$ES_URL/$INDEX" >/dev/null || true

curl -sS --fail --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
  -H 'Content-Type: application/json' \
  -X PUT "$ES_URL/$INDEX" -d "{
    \"settings\": {
      \"number_of_shards\": $SHARDS,
      \"number_of_replicas\": $REPLICAS,
      \"refresh_interval\": \"1s\"
    },
    \"mappings\": {
      \"properties\": {
        \"ts\": {\"type\": \"date\"},
        \"user\": {\"type\": \"keyword\"},
        \"msg\": {\"type\": \"text\"},
        \"value\": {\"type\": \"double\"}
      }
    }
  }" | jq .

echo "[setup] done"