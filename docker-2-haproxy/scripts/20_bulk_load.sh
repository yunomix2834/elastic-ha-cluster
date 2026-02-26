#!/usr/bin/env bash
set -euo pipefail

ES_URL="${ES_URL:-https://haproxy-1:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"
CA_CERT="${CA_CERT:-/certs/ca/ca.crt}"

INDEX="${INDEX:-bench_docs}"

# knobs
BULK_DOCS="${BULK_DOCS:-1000}"          # docs per bulk request
BULK_ITERS="${BULK_ITERS:-50}"          # number of bulk requests
MSG_SIZE="${MSG_SIZE:-200}"             # chars in msg
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"     # seconds

tmp="$(mktemp)"
bulk_body="$(mktemp)"

gen_msg() {
  # generate pseudo text length MSG_SIZE
  head -c "$MSG_SIZE" /dev/urandom | base64 | tr -d '\n' | head -c "$MSG_SIZE"
}

echo "[bulk] index=$INDEX docs_per_bulk=$BULK_DOCS iters=$BULK_ITERS msg_size=$MSG_SIZE"

# prepare one bulk payload template (ndjson)
: > "$bulk_body"
for i in $(seq 1 "$BULK_DOCS"); do
  echo "{\"index\":{\"_index\":\"$INDEX\"}}" >> "$bulk_body"
  m="$(gen_msg)"
  # simple doc
  echo "{\"ts\":\"$(date -Iseconds)\",\"user\":\"u$((RANDOM%100))\",\"value\":$((RANDOM%10000))/100,\"msg\":\"$m\"}" >> "$bulk_body"
done

total_docs=0
ok_reqs=0
err_reqs=0
sum_ms=0
min_ms=999999
max_ms=0
start_all=$(date +%s%3N)

for iter in $(seq 1 "$BULK_ITERS"); do
  t0=$(date +%s%3N)
  http_code=$(curl -sS -o "$tmp" -w "%{http_code}" \
    --cacert "$CA_CERT" -u "$ES_USER:$ES_PASS" \
    -H 'Content-Type: application/x-ndjson' \
    -X POST "$ES_URL/_bulk?refresh=false" \
    --data-binary @"$bulk_body" || true)
  t1=$(date +%s%3N)
  dt=$((t1-t0))

  if (( dt < min_ms )); then min_ms=$dt; fi
  if (( dt > max_ms )); then max_ms=$dt; fi
  sum_ms=$((sum_ms+dt))

  if [[ "$http_code" != "200" ]]; then
    err_reqs=$((err_reqs+1))
    echo "[bulk][$iter] HTTP $http_code dt=${dt}ms"
  else
    # check bulk errors field
    has_errors=$(jq -r '.errors' "$tmp" 2>/dev/null || echo "true")
    if [[ "$has_errors" == "true" ]]; then
      err_reqs=$((err_reqs+1))
      echo "[bulk][$iter] BULK_ERRORS dt=${dt}ms"
      jq '.items[0]' "$tmp" >/dev/null 2>&1 || true
    else
      ok_reqs=$((ok_reqs+1))
      total_docs=$((total_docs+BULK_DOCS))
      echo "[bulk][$iter] OK dt=${dt}ms"
    fi
  fi

  if [[ "$SLEEP_BETWEEN" != "0" ]]; then sleep "$SLEEP_BETWEEN"; fi
done

end_all=$(date +%s%3N)
wall_ms=$((end_all-start_all))
wall_s=$(python3 - <<PY
print(${wall_ms}/1000)
PY
)

avg_ms=$(python3 - <<PY
ok=${ok_reqs}+${err_reqs}
print(round(${sum_ms}/max(ok,1),2))
PY
)

docs_per_s=$(python3 - <<PY
docs=${total_docs}
sec=${wall_ms}/1000
print(round(docs/max(sec,0.001),2))
PY
)

echo
echo "===== BULK SUMMARY ====="
echo "total_docs=$total_docs"
echo "requests_ok=$ok_reqs requests_err=$err_reqs"
echo "latency_ms avg=$avg_ms min=$min_ms max=$max_ms"
echo "wall_s=$wall_s docs_per_s=$docs_per_s"
echo "========================"