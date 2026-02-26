#!/usr/bin/env bash
set -euo pipefail

ES_URL="${ES_URL:-https://haproxy-1:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"
CA_CERT="${CA_CERT:-/certs/ca/ca.crt}"

echo "[smoke] ES_URL=$ES_URL"

curl -sS --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
  "$ES_URL" | jq .

curl -sS --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
  "$ES_URL/_cluster/health?pretty" | jq .

curl -sS --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
  "$ES_URL/_cat/nodes?v" | sed 's/^/[nodes] /'