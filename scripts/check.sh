#!/usr/bin/env sh
# version 4.0.1
set -eu
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then
  echo 'Missing .env; copy .env.example and configure it first.' >&2
  exit 1
fi
proxy_ip="${1:-$(sed -n 's/^PROXY_IP=//p' .env | tail -n 1)}"
case "$proxy_ip" in
  ''|REPLACE_*) echo 'Set PROXY_IP in .env or supply it as the first argument.' >&2; exit 1 ;;
esac
echo '== Containers =='
docker compose ps
echo '== Nginx SNI allowlist =='
docker compose exec -T proxy nginx -T 2>&1 | grep -E '(^[[:space:]]+(www\.|api\.|i\.|s\.)?imgur\.com[[:space:]]+)' || true
echo '== VPN public IP =='
docker compose exec -T proxy wget -qO- -T 10 https://api.ipify.org || true
echo
echo '== TLS / HTTP checks (run from a machine that can access the macvlan IP) =='
for host in imgur.com www.imgur.com i.imgur.com s.imgur.com api.imgur.com; do
  printf '%-18s ' "$host"
  curl -sS --connect-timeout 8 --max-time 20 --resolve "$host:443:$proxy_ip" -o /dev/null -w 'HTTP %{http_code} | remote %{remote_ip}\n' "https://$host/" || true
done
