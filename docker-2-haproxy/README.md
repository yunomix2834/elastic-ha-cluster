### Chaỵ Docker
```shell
chmod +x rally-work/rally-entrypoint.sh
```

```shell
docker compose up -d setup-certs
docker compose up -d
docker compose ps
```

Nếu kibana bị lỗi thì chạy lại
```shell
docker compose up -d
```

Tài khoản mật khẩu admin mặc định là elastic/ElasticRoot@123, có thể thay đổi trong file docker-compose.yml
Cổng kibana: https://localhost:15601

### Test tải, đọc metrics
Check dependencies trong es-rally
```shell
docker compose exec rally sh -lc '
  set -eux
  git --version
  nslookup github.com || true
  ping -c 1 github.com || true
  curl -I https://github.com/elastic/rally-tracks || true
  git ls-remote https://github.com/elastic/rally-tracks | head -n 5 || true
'
```

Smoke test + check cluster health
```shell
docker compose exec toolbox bash -lc "chmod +x /scripts/00_smoke.sh && /scripts/00_smoke.sh"
```

Bulk ingest load test (curl + đo throughput / latency)
Ý tưởng: tạo NDJSON bulk body ngay trong bash, đẩy lặp nhiều lần, đo:
- tổng docs/s
- latency per request (avg/min/max)
- error rate (HTTP != 200 hoặc bulk errors:true)
```shell
docker compose exec toolbox bash -lc "
  chmod +x /scripts/10_setup_index.sh /scripts/20_bulk_load.sh &&
  /scripts/10_setup_index.sh &&
  BULK_DOCS=2000 BULK_ITERS=30 MSG_SIZE=500 /scripts/20_bulk_load.sh
"
```

Search load test (ab hoặc vòng curl) + latency percentiles
ab (apachebench) có sẵn trong toolbox. Nó cho RPS, mean latency, percentiles cơ bản.
```shell
docker compose exec toolbox bash -lc '
  N=10000 C=300 TIMEOUT=180 KEEPALIVE=false /scripts/31_ab_search.sh
'
```

Collect mertrics: node stats + index stats + threadpool + JVM
```shell
docker compose exec toolbox bash -lc "
  chmod +x /scripts/40_collect_metrics.sh &&
  OUT_DIR=/scripts/out /scripts/40_collect_metrics.sh
"
```

ES Rally: đo thoughput/latency percentiles
- Throughput (ops/s)
- Latency (50th/90th/99th)
- Service time
- Error rate
- Và tóm tắt track/challenge

Tìm đường dẫn của esrally
```shell
docker compose exec rally sh -lc '
  python -c "import sys; print(sys.executable); import site; print(site.getsitepackages())"
  python -m pip -V
  python -m pip show esrally | sed -n "1,60p"
  ls -la /usr/local/bin | grep -i rally || true
  command -v esrally || true
'
```

Sau đó thay đường dẫn vào trước esrally
```shell
docker compose exec rally sh -lc '    
  ES_HOST="haproxy-1"
  ES_PORT="9200"
  ES_USER="elastic"
  ES_PASS="ElasticRoot@123"
  CA="/certs/ca/ca.crt"

  /usr/local/bin/esrally race \
    --pipeline=benchmark-only \
    --target-hosts="${ES_HOST}:${ES_PORT}" \
    --client-options="use_ssl:true,verify_certs:true,ca_certs:${CA},basic_auth_user:${ES_USER},basic_auth_password:${ES_PASS}" \
    --track=geonames \
    --challenge=append-no-conflicts \
    --report-format=markdown
'
```
