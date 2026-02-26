#!/usr/bin/env sh
set -eu

echo "[rally] booting..."

apt-get update
apt-get install -y --no-install-recommends \
  git ca-certificates curl dnsutils iputils-ping jq procps
rm -rf /var/lib/apt/lists/*

git config --global http.version HTTP/1.1 || true
git config --global http.lowSpeedLimit 1 || true
git config --global http.lowSpeedTime 300 || true

python -m pip install --no-cache-dir --upgrade pip
python -m pip install --no-cache-dir esrally

set -eux
rm -rf /root/.rally/benchmarks/tracks/default
mkdir -p /root/.rally/benchmarks/tracks

git config --global http.version HTTP/1.1
git config --global http.lowSpeedLimit 1
git config --global http.lowSpeedTime 300

git clone --depth 1 https://github.com/elastic/rally-tracks /root/.rally/benchmarks/tracks/default
ls -la /root/.rally/benchmarks/tracks/default | head
set +eux

echo "[rally] versions:"
git --version
curl --version | head -n 1
/usr/local/bin/esrally --version

echo "[rally] ready (sleeping)..."
tail -f /dev/null