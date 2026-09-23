# Monitoring (optional)

The server side is the NixOS module (`services.valheim.monitoring`). This
directory holds the pieces for **your** Prometheus / Loki / Grafana, wherever
they run. Nothing here is required to run the game server.

| What | Where it comes from |
|---|---|
| Host metrics, `podman-valheim.service` up/down | node_exporter on the server, `:9100` |
| Backup freshness (`valheim_backup_*`) | node_exporter textfile collector, written after each restic run |
| Server log, player count, join/leave events | journal → Alloy → Loki, label `host` |

There is no game-side exporter. With `-crossplay` the server never answers
Steam A2S queries, so the player count comes from the `Connections N` line the
server logs every 10 minutes.

## Prometheus

Add a scrape job pointing at the server, and list the Prometheus host in
`services.valheim.monitoring.nodeExporter.allowedSources` so the firewall lets
it through:

```yaml
scrape_configs:
  - job_name: "valheim-node"
    static_configs:
      - targets: ["valheim.lan:9100"]
```

## Loki

Alloy pushes over HTTP to `services.valheim.monitoring.loki.url`. Loki must be
reachable from the server: publish its port on the LAN interface only (for
Docker, `ports: ["<lan-ip>:3100:3100"]`, not `3100:3100`), or reach it over
Tailscale/WireGuard. Loki has no authentication by default, so never expose
it to the internet.

## Grafana

Import [`grafana/valheim.json`](grafana/valheim.json) (Dashboards → New →
Import), or drop it into a file-provisioned dashboards folder. It has
datasource pickers for Prometheus and Loki, an instance picker, and a `host`
text box that must match `services.valheim.monitoring.loki.hostLabel`
(defaults to the server's hostname).

Tiles:

- **Players online / over time / events**: from the log heartbeat; fills in after the first 10 min.
- **Game server**: `node_systemd_unit_state{name="podman-valheim.service"}`.
- **Last good backup / result**: turn orange after 3 h and red after 6 h without a successful restic run.
- **CPU, temperature, memory, disk, network, server log**.
