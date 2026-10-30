<!-- version 4.0.1 -->
<p align="center">
  <img src="imgur_github.png" alt="Imgur Proxy" />
</p>

# SWImgur — network-wide Imgur VPN proxy

**Access Imgur on your LAN using Private Internet Access (PIA), Gluetun, Nginx, Docker Compose and AdGuard Home — without installing a VPN on every device.**

SWImgur uses AdGuard DNS rewrites to direct selected Imgur hostnames to an Nginx TCP proxy. Nginx routes TLS connections through a PIA VPN via Gluetun, without decrypting HTTPS or requiring local TLS certificates.

> 📝 Original write-up: [Imgur said 403 Forbidden](https://makes.swakes.co.uk/imgur-said-403-forbidden/).
>
> This is a community project, unaffiliated with Imgur, PIA, Gluetun or AdGuard. Imgur may restrict particular VPN exit servers, and site availability is not guaranteed.

## How it works

```text
Browser / app → AdGuard Home DNS rewrite → SWImgur macvlan IP:443
                                             ↓
                                   Nginx SNI passthrough
                                             ↓
                                      Gluetun + PIA
                                             ↓
                                  Public Imgur endpoints
```

Only the selected Imgur traffic uses the VPN; other requests from clients use their normal connection.

### Supported hostnames

| Domain | Purpose |
|---|---|
| `imgur.com` | Website |
| `www.imgur.com` | Website alias |
| `i.imgur.com` | Images |
| `s.imgur.com` | JavaScript, CSS, assets |
| `api.imgur.com` | Search, account, feeds and other API calls |

Both the Nginx SNI allowlist and DNS rewrites must include **all five** names for the full site to function. This is *not* an unrestricted network proxy.

## Requirements

- Linux Docker host with Docker Engine and Compose plugin (ARM64 Raspberry Pi OS or x86_64)
- PIA subscription and **PIA VPN credentials** (these may differ from the website login)
- `/dev/net/tun` available
- AdGuard Home, Pi-hole or a similar DNS rewrite service used by LAN clients
- A wired interface supporting Docker macvlan, an unused LAN IP address, and the LAN subnet/gateway
- No conflicting device using the chosen address

## Installation

### 1. Clone and configure

```bash
# version 4.0.1
git clone https://github.com/pqpxo/imgur-proxy.git
cd imgur-proxy
cp .env.example .env
nano .env
chmod 600 .env
```

In `.env`, supply `PIA_USER`, `PIA_PASSWORD`, `SERVER_REGIONS`, `PROXY_IP` and `MACVLAN_NETWORK`. **Never commit .env**.

`PROXY_IP` is an unused address belonging to the **SWImgur container** on your LAN — it is not the Docker host or AdGuard's address. Reserve/exclude it from DHCP.

### 2. Create a macvlan network

Inspect your interface (`ip link`) and route (`ip route`). If you already have a suitable macvlan network, reuse it. Otherwise create one. **The following is a fictional example; replace all LAN values and the parent interface.**

```bash
# version 4.0.1
docker network create -d macvlan \
  --subnet=192.168.50.0/24 \
  --gateway=192.168.50.1 \
  -o parent=eth0 swimgur-macvlan
```

Set `MACVLAN_NETWORK=swimgur-macvlan` and a free address such as `PROXY_IP=192.168.50.200` in your private `.env` (only if those example values match your network). Linux hosts typically cannot access their own macvlan containers without a shim interface; test from another LAN device.

### 3. Deploy

```bash
# version 4.0.1
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs --tail=60 vpn
```

The proxy waits for Gluetun's VPN health check before starting.

### 4. Configure AdGuard Home

Under **Filters → DNS rewrites**, point each hostname to **your `PROXY_IP`**:

| Domain | DNS answer |
|---|---|
| `imgur.com` | `YOUR_PROXY_IP` |
| `www.imgur.com` | `YOUR_PROXY_IP` |
| `i.imgur.com` | `YOUR_PROXY_IP` |
| `s.imgur.com` | `YOUR_PROXY_IP` |
| `api.imgur.com` | `YOUR_PROXY_IP` |

Ensure devices actually use AdGuard rather than an alternative public DNS resolver or browser DNS-over-HTTPS. Verify IPv6 behaviour if relevant. **Never expose TCP 443 of the proxy to the public WAN.**

### 5. Test from another LAN machine

```bash
# version 4.0.1
nslookup imgur.com YOUR_ADGUARD_IP
curl -I --resolve imgur.com:443:YOUR_PROXY_IP https://imgur.com/
curl -I --resolve s.imgur.com:443:YOUR_PROXY_IP https://s.imgur.com/
curl -I --resolve api.imgur.com:443:YOUR_PROXY_IP https://api.imgur.com/
```

A successful TLS handshake and HTTP response prove forwarding; 302 redirects are sometimes expected. A 403/429 can indicate an Imgur-side restriction or rate limit on the VPN exit. The bare API root may also reject requests without the correct endpoint/client ID. Finally test an actual image and the website's Search, Sign in, and feeds.

Inspect the running Nginx configuration and the VPN exit:

```bash
# version 4.0.1
docker compose exec proxy nginx -T
docker compose exec proxy wget -qO- https://api.ipify.org
```

Do not post your real WAN IP publicly. A diagnostic helper is available in `scripts/check.sh`; the macvlan reachability portion should be run from a separate LAN machine.

## Updating and troubleshooting

**Nginx configuration is copied into the Docker image at build time. A plain container restart does not load new `nginx.conf` contents.** Rebuild and recreate:

```bash
# version 4.0.1
docker compose build --no-cache proxy
docker compose up -d --no-deps --force-recreate proxy
docker compose exec proxy nginx -t
```

For general image updates:

```bash
# version 4.0.1
docker compose pull vpn
docker compose build --pull proxy
docker compose up -d
```

| Symptom | Check |
|---|---|
| TLS handshake fails for a hostname | Check its AdGuard rewrite and `docker compose exec proxy nginx -T`; rebuild after changing `nginx.conf` |
| Regional restriction in browser, but forced curl works | Client DNS, secondary resolver, browser DoH, local DNS caches, hosts file, proxy settings |
| Website blank | `s.imgur.com` must use the proxy |
| Search / login / feeds not working | `api.imgur.com` must use the proxy; check browser Network → XHR |
| 403 or 429 through proxy | Imgur may block/rate-limit your VPN exit |
| Docker host cannot reach proxy IP | Expected macvlan host-isolation limitation |
| Startup DNS warning | Check whether Gluetun recovers and stays healthy |

Avoid proxying random ad/tracker domains just because the browser lists blocked requests.

## Security and privacy

- Nginx forwards **TLS over TCP** by reading SNI and does not terminate/decrypt HTTPS.
- Only the five listed hostnames are forwarded. Unknown names are rejected.
- VPN egress uses Gluetun's network namespace and firewall; keep the proxy accessible only to trusted LAN clients.
- `.env`, Gluetun state and backups are ignored by Git and excluded from Docker build context.
- **Security notice for existing forks:** Older versions of this repository committed a `.env` file. Even after deleting it from the latest branch, those values may remain in Git history. Rotate any credentials that were present; consider purging sensitive history separately.

## Files

```text
imgur-proxy/
├── README.md
├── imgur_github.png
├── docker-compose.yml
├── Dockerfile
├── nginx.conf
├── .env.example
├── .gitignore
├── .dockerignore
├── scripts/check.sh
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE).
