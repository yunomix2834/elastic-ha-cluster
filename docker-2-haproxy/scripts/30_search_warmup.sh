#!/usr/bin/env bash
set -euo pipefail

ES_URL="${ES_URL:-https://haproxy-1:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"
CA_CERT="${CA_CERT:-/certs/ca/ca.crt}"
INDEX="${INDEX:-bench_docs}"

curl -sS --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
  -H 'Content-Type: application/json' \
  -X POST "$ES_URL/$INDEX/_search" -d '{
    "size": 10,
    "query": {"match": {"msg": "a"}}
  }' >/dev/null

echo "[warmup] done"