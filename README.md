<p align="center">
  <img src="imgur_github.png" alt="Imgur Proxy Setup" />
</p>

# imgur-proxy

A network-level Imgur proxy for UK users, built with Gluetun, Nginx, and AdGuard Home. Routes all Imgur traffic through a VPN exit node transparently - no client configuration required.

> 📖 Full write-up on my blog: [makes.swakes.co.uk](https://makes.swakes.co.uk/imgur-said-403-forbidden/)

---

## Overview

Imgur geo-blocks UK users. Rather than running a VPN on every device, this setup intercepts Imgur DNS requests at the network level and proxies traffic through a VPN-connected Docker container. Every device on your LAN gets working Imgur images automatically.



```
Device → AdGuard DNS rewrite → Gluetun macvlan IP → Nginx TCP passthrough → PIA VPN → Imgur
```

## Requirements

- Docker & Docker Compose
- [AdGuard Home](https://adguard.com) (or Pi-hole) as your network DNS
- [Private Internet Access](https://www.privateinternetaccess.com/) subscription
- A free IP on your LAN (e.g. `192.168.1.200`)

---

## Setup

### 1. Create the macvlan Docker network

```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  --ip-range=192.168.1.200/32 \
  -o parent=eth0 \
  imgur-macvlan
```

> Replace values to match your LAN. Check your interface with `ip link`.

### 2. Clone this repo

```bash
git clone https://github.com/pqpxo/imgur-proxy.git
cd imgur-proxy
```

### 3. Create your `.env` file

```bash
cp .env.example .env
```

Edit `.env` with your PIA credentials:

```env
PIA_USER=your_pia_username
PIA_PASSWORD=your_pia_password
SERVER_REGIONS=Netherlands
```

### 4. Deploy

```bash
docker compose up -d
```

### 5. Add AdGuard DNS rewrites

In AdGuard Home → **Filters → DNS rewrites**, add:

| Domain | Answer |
|---|---|
| `i.imgur.com` | `192.168.1.200` |
| `imgur.com` | `192.168.1.200` |
| `www.imgur.com` | `192.168.1.200` |

---

## File Structure

```
imgur-proxy/
├── docker-compose.yml
├── nginx.conf
├── .env.example
└── README.md
```

---

## Verifying It Works

From any device on your network (not the Docker host):

```bash
curl -vI --resolve imgur.com:443:192.168.1.200 https://imgur.com
```

Check the `X-Served-By` header - it should show an Amsterdam or Frankfurt cache node, not London (`LCY`).

---

## Notes

- The Docker host itself cannot reach the macvlan IP - this is a known Linux macvlan limitation. All other LAN devices work fine.
- The Nginx `stream {}` block does TCP passthrough only - TLS is never terminated, traffic is never decrypted.
- `imgur.com` main site may still return 403 errors - Imgur have largely abandoned it as a platform. The real value here is `i.imgur.com` image loading in Reddit threads, forums, and READMEs.
- To change VPN region, update `SERVER_REGIONS` in `.env` and run `docker compose down && docker compose up -d`.

---

## License

MIT
