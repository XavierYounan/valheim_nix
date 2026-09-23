# valheim_nix

A Valheim dedicated server as a NixOS module. Point it at a spare machine
(an old laptop works well) and it runs the server in a Podman container,
keeps it running through reboots and flaky networks, and can optionally back
up your worlds off-box and report to Prometheus, Loki and Grafana.

```nix
services.valheim = {
  enable = true;
  openFirewall = true;
  crossplay = true;
};
```

- **Server**: [`lloesche/valheim-server`](https://github.com/lloesche/valheim-server-docker)
  under Podman, managed by systemd. Self-updates from Steam, zips the world every 2 h.
- **Backups (optional)**: encrypted, deduplicated [restic](https://restic.net) snapshots
  to SFTP, S3, B2 or anything restic supports, with retention and integrity checks.
- **Monitoring (optional)**: node_exporter locked to your Prometheus's IP, the
  journal shipped to Loki with Grafana Alloy, and a ready-made Grafana dashboard.
- **Secrets stay off the Nix store**: the server password and restic password are
  runtime files. The module refuses to build if you point them at the store.

## Quick start

You need a machine to install NixOS on and a workstation with
[Nix](https://nixos.org/download) installed.

```bash
mkdir my-valheim && cd my-valheim
nix flake init -t github:XavierYounan/valheim_nix
```

This gives you a private **host flake** (`flake.nix` + `configuration.nix`)
that imports this repo's module. Add your SSH key to `configuration.nix`, then
follow the [runbook](docs/RUNBOOK.md) to install NixOS, add the generated
`hardware-configuration.nix`, create the secrets file and open the router.

Keep the host flake in a **private** repo. It will hold your
hardware configuration, LAN addresses and SSH keys. This repo holds none of
those.

Already running NixOS with flakes? Add the input and module to your flake:

```nix
inputs.valheim-nix.url = "github:XavierYounan/valheim_nix";
# ...
modules = [ valheim-nix.nixosModules.default ./configuration.nix ];
```

## Options

All options are under `services.valheim`.

| Option | Default | |
|---|---|---|
| `enable` | `false` | Run the server. |
| `openFirewall` | `false` | Open UDP `port` and `port + 1`. |
| `port` | `2456` | First game port. |
| `public` | `false` | List in the Steam / in-game server browser. |
| `crossplay` | `false` | Join codes for consoles/Game Pass, relays through CGNAT. Disables Steam A2S queries. |
| `image` | `ghcr.io/lloesche/valheim-server:latest` | Pin by `@sha256:` digest for reproducible deploys. |
| `dataDir` | `/var/lib/valheim` | Worlds in `config/`, server install in `data/`. |
| `environmentFile` | `${dataDir}/env` | `SERVER_NAME`, `WORLD_NAME`, `SERVER_PASS`. See [`env.example`](env.example). |
| `timeZone` | `time.timeZone` or `UTC` | For the container's schedules and logs. |
| `updateCron` | `*/15 * * * *` | Steam update check. |
| `worldBackups.cron` / `.maxAgeDays` | `0 */2 * * *` / `7` | The container's own world zips. |
| `extraEnvironment` | `{}` | Any other [image variable](https://github.com/lloesche/valheim-server-docker#environment-variables). Not for secrets. |
| `backup.restic.enable` | `false` | Off-box restic snapshots of `config/`. |
| `backup.restic.repository` | | e.g. `sftp:backup@nas.lan:backups/valheim`. |
| `backup.restic.passwordFile` | `${dataDir}/restic-password` | |
| `backup.restic.environmentFile` | `null` | Cloud backend credentials. |
| `backup.restic.schedule` | `00/2:30` | systemd calendar spec. |
| `backup.restic.pruneOpts` / `checkOpts` | 24h/14d/8w/12m, 10 % read | |
| `monitoring.nodeExporter.enable` | `false` | Host metrics + backup freshness on `:9100`. |
| `monitoring.nodeExporter.allowedSources` | `[]` | IPv4 addresses allowed to scrape. Empty = port closed. |
| `monitoring.loki.enable` | `false` | Ship the journal with Alloy. |
| `monitoring.loki.url` | | Loki push URL. |
| `monitoring.loki.hostLabel` | hostname | `host` label on log lines. |

## Docs

- [Runbook](docs/RUNBOOK.md): install, first boot, router, updates, backups, restore, troubleshooting.
- [Monitoring](monitoring/README.md): Prometheus, Loki and the Grafana dashboard.
- [Security](SECURITY.md): what the defaults protect against, and what they don't.

## Development

```bash
nix flake check   # builds a CI system with every option switched on
nix fmt
```

## License

[MIT](LICENSE). Valheim is a trademark of Iron Gate AB. This project is not affiliated with Iron Gate or Coffee Stain.
