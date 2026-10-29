# Changelog

## 2026-10-29

### Proxying

Caddy no longer connects to `xray:443`. Caddy treats port 443 as HTTPS, while Xray accepts plain TCP on its internal port. The main Xray inbound listens on `8080`, and Caddy proxies WebSocket traffic to `http://xray:8080`. Ports 80 and 443 stay open on Caddy for the outside world, and client links still use port 443.

### Images

- Caddy: `caddy:2.11.7-alpine`
- Xray: `teddysun/xray:26.10.21`
- Removed `flow: xtls-rprx-direct` from the config. Xray 1.8 and later reject that mode. The VLESS/VMESS over WebSocket links do not use it.

### Installer

- Commands now use `docker compose`. The separate `docker-compose` check is gone: the plugin is installed with Docker.
- The config lives in `xray/config.json`. `docker-compose.yml` mounts the `./xray` directory, because `VOLUME /etc/xray` in the image hides a single-file bind.
