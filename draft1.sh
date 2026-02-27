#!/usr/bin/env bash
set -euo pipefail

ES_URL="${ES_URL:-https://haproxy-1:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-ElasticRoot@123}"
CA_CERT="${CA_CERT:-/certs/ca/ca.crt}"

INDEX="${INDEX:-bench_docs}"

BULK_DOCS="${BULK_DOCS:-1000}"
BULK_ITERS="${BULK_ITERS:-50}"
MSG_SIZE="${MSG_SIZE:-200}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"

tmp="$(mktemp)"
bulk_body="$(mktemp)"

gen_msg() {
  head -c "$MSG_SIZE" /dev/urandom | base64 | tr -d '\n' | head -c "$MSG_SIZE"
}

# random float 0..100 with 2 decimals (JSON hợp lệ)
rand_float() {
  awk -v r="$RANDOM" 'BEGIN{ printf "%.2f", (r/32767.0)*100 }'
}

echo "[bulk] index=$INDEX docs_per_bulk=$BULK_DOCS iters=$BULK_ITERS msg_size=$MSG_SIZE"

: > "$bulk_body"
for i in $(seq 1 "$BULK_DOCS"); do
  echo "{\"index\":{\"_index\":\"$INDEX\"}}" >> "$bulk_body"
  m="$(gen_msg)"
  v="$(rand_float)"
  echo "{\"ts\":\"$(date -Iseconds)\",\"user\":\"u$((RANDOM%100))\",\"value\":$v,\"msg\":\"$m\"}" >> "$bulk_body"
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

  (( dt < min_ms )) && min_ms=$dt
  (( dt > max_ms )) && max_ms=$dt
  sum_ms=$((sum_ms+dt))

  if [[ "$http_code" != "200" ]]; then
    err_reqs=$((err_reqs+1))
    echo "[bulk][$iter] HTTP $http_code dt=${dt}ms"
    continue
  fi

  has_errors=$(jq -r '.errors' "$tmp" 2>/dev/null || echo "true")
  if [[ "$has_errors" == "true" ]]; then
    err_reqs=$((err_reqs+1))
    echo "[bulk][$iter] BULK_ERRORS dt=${dt}ms"
    # in nhanh 1 error điển hình để biết nguyên nhân
    jq -r '
      .items[]
      | (..|.error? // empty)
      | "  reason=" + (.reason // "n/a") + " type=" + (.type // "n/a")
      ' "$tmp" | head -n 1 || true
  else
    ok_reqs=$((ok_reqs+1))
    total_docs=$((total_docs+BULK_DOCS))
    echo "[bulk][$iter] OK dt=${dt}ms"
  fi

  [[ "$SLEEP_BETWEEN" != "0" ]] && sleep "$SLEEP_BETWEEN"
done

end_all=$(date +%s%3N)
wall_ms=$((end_all-start_all))

reqs=$((ok_reqs+err_reqs))
avg_ms=$(awk -v s="$sum_ms" -v r="$reqs" 'BEGIN{ if(r==0) r=1; printf "%.2f", s/r }')
wall_s=$(awk -v ms="$wall_ms" 'BEGIN{ printf "%.3f", ms/1000.0 }')
docs_per_s=$(awk -v d="$total_docs" -v ms="$wall_ms" 'BEGIN{ sec=ms/1000.0; if(sec<0.001) sec=0.001; printf "%.2f", d/sec }')

echo
echo "===== BULK SUMMARY ====="
echo "total_docs=$total_docs"
echo "requests_ok=$ok_reqs requests_err=$err_reqs"
echo "latency_ms avg=$avg_ms min=$min_ms max=$max_ms"
echo "wall_s=$wall_s docs_per_s=$docs_per_s"
echo "========================"