# Security

## Reporting

Please report vulnerabilities privately through GitHub's
**Security → Report a vulnerability** on this repository rather than in a public issue.

## What the module does

- **No secrets in the Nix store or in git.** `SERVER_PASS` and the restic password
  are runtime files under `/var/lib/valheim` (mode `0700` directory, `0600` files).
  Their options are strings, not Nix paths, so they are never copied into the
  world-readable store, and an assertion fails the build if you point one at
  `/nix/store`. `extraEnvironment` values *do* land in the store: don't put secrets there.
- **Minimal exposure.** Only the two UDP game ports are opened, and only when
  `openFirewall = true`. node_exporter is firewalled to the exact IPv4 addresses in
  `allowedSources` (validated before being spliced into iptables) and closed to
  everyone else. Alloy's debug UI listens on `127.0.0.1` only, and its telemetry
  to Grafana Labs is disabled.
- **Encrypted backups.** restic encrypts client-side; the backup host only sees
  ciphertext. `restic check` reads back 10 % of the data after every run.

## What the host template does

- SSH: keys only, no root login, `AllowUsers` limited to the admin user, fail2ban.
- sudo requires a password (`wheelNeedsPassword = true`).
- Tailscale is suggested for remote admin so SSH need not be port-forwarded.

## Things to know

- **The container runs as root under rootful Podman**, like most deployments of
  the upstream image. It has the default Podman capability set plus `SYS_NICE`.
  A container escape via a Valheim or image vulnerability would be root on the host.
  Treat the server as a single-purpose machine.
- **The image is `:latest` by default** and the game auto-updates from Steam. Pin
  `services.valheim.image` to a digest if you want to review changes before they run.
- **`nix.settings.trusted-users`** in the template lets the admin user push unsigned
  store paths, which is equivalent to root. Remove it if you build on the server itself.
- **Loki pushes are plain HTTP without auth.** Keep Loki on a trusted LAN or VPN.
  Logs include player names and Steam/PlayFab IDs.
- **SFTP backups use root's SSH key.** On the backup host, restrict that key in
  `authorized_keys` to SFTP only (`restrict,command="internal-sftp"` or the path to
  your `sftp-server`) and pin the backup host's key with `programs.ssh.knownHosts`.
  A compromised game server can still delete or overwrite its own backups; for
  protection against that, use an append-only repository
  (`rest-server --append-only`) or backend object lock.
- **`public = true`** only lists the server in the browser; the password still
  gates entry. Anyone with the password can join and modify the world, so use
  a long random one and add admins/bans in `config/adminlist.txt` / `bannedlist.txt`.
- **The machine does not patch itself.** Run `nix flake update` and redeploy
  regularly (see the runbook).
