# Runbook

From a blank machine to friends joining your world, then keeping it running.

Conventions used below. Substitute your own values:

| Placeholder | Meaning |
|---|---|
| `<installer-ip>` | The machine's LAN IP while booted from the NixOS USB |
| `<server-ip>` | The machine's reserved LAN IP after install, e.g. `192.168.1.50` |
| `<public-ip>` | Your router's WAN address |
| `admin` | The admin user from the host template |
| `~/my-valheim` | Your private host flake (from `nix flake init -t ...`) |

Everything is driven from a workstation that has Nix installed and an SSH key.

---

## 0. Before you start

- **Is your connection reachable?** Check the router's WAN/Internet status page.
  If the WAN address is in `100.64.0.0/10`, you're behind CGNAT: port forwarding
  won't work. Use `crossplay = true` (players join by code through PlayFab relays)
  or ask your ISP for a public IP.
- **Hardware**: dual-core CPU, 4 GB RAM minimum (8+ comfortable), 10 GB+ disk, wired
  Ethernet strongly preferred.

## 1. Flash the installer

Download the **minimal ISO** for x86_64 from <https://nixos.org/download/#nixos-iso> and
write it to a USB stick. Triple-check the device: this wipes it.

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN          # the stick has TRAN=usb
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## 2. Firmware settings

In the BIOS/UEFI setup:

- **Secure Boot: Disabled.** systemd-boot isn't signed.
- **SATA mode: AHCI**, **boot mode: UEFI.**
- Boot from the USB stick (one-time boot menu).

## 3. SSH into the installer

At the installer console:

```bash
sudo -i
passwd                        # temporary, lives in RAM only
ip -4 addr show | grep inet   # note <installer-ip>
```

From the workstation: `ssh root@<installer-ip>`.

## 4. Partition and mount

**This erases the target disk.** Confirm which one it is first; below it's `/dev/sda`.

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN

parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 1GiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart root ext4 1GiB 100%

mkfs.fat -F 32 -n BOOT /dev/sda1
mkfs.ext4 -L nixos /dev/sda2

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/BOOT /mnt/boot
```

No swap partition: the template enables zram.

## 5. Host flake and hardware config

On the workstation, create your private host flake if you haven't:

```bash
mkdir ~/my-valheim && cd ~/my-valheim
nix flake init -t github:XavierYounan/valheim_nix
git init
```

Edit `configuration.nix`:

- **Add your SSH public key** to `users.users.admin.openssh.authorizedKeys.keys`.
  Password SSH is off, so without one you're locked out.
- Set `time.timeZone`, `networking.hostName`, and the `services.valheim` options you want.
- Old laptop? Uncomment the headless-laptop block.

Generate the hardware config on the installer and pull it into the flake:

```bash
ssh root@<installer-ip> nixos-generate-config --root /mnt
scp root@<installer-ip>:/mnt/etc/nixos/hardware-configuration.nix .
git add -A && git commit -m "valheim host"
nix flake check
```

Flakes only see files git knows about, so `git add` before every build.

## 6. Install

Copy the flake to the target disk and install from it:

```bash
scp -r ~/my-valheim/. root@<installer-ip>:/mnt/etc/nixos/
# A flake inside a git checkout only sees committed files; drop .git from the copy.
ssh root@<installer-ip> 'rm -rf /mnt/etc/nixos/.git; nixos-install --flake /mnt/etc/nixos#valheim --no-root-passwd'
```

Expect 5-15 minutes while it downloads packages.

Before rebooting, set the admin password (needed for sudo):

```bash
ssh root@<installer-ip> 'nixos-enter --root /mnt -c "passwd admin"' && ssh root@<installer-ip> reboot
```

Pull the USB stick once the screen goes dark.

## 7. Secrets and first start

```bash
ssh admin@<installer-ip>        # DHCP may hand out the same IP; check the router if not
```

Create the server secrets file. It never goes in git:

```bash
sudo install -m 600 /dev/null /var/lib/valheim/env
sudoedit /var/lib/valheim/env      # contents: see env.example
sudo systemctl restart podman-valheim
journalctl -fu podman-valheim
```

`SERVER_PASS` must be at least 5 characters and must not appear inside `SERVER_NAME`,
or the server refuses to start. The first start pulls the image and ~1 GB of server
files: 5-10 minutes. It's up when the log says `Game server connected`.
With `crossplay = true`, the log also prints the **join code**.

## 8. Router

1. **DHCP reservation**: bind the machine's MAC (`ip link show`) to `<server-ip>`.
2. **Port forward**: UDP `2456-2457` → `<server-ip>` (not needed if you only use crossplay join codes).
   TCP is not needed. **Do not forward 22.** Use Tailscale for remote admin.
3. If your public IP is dynamic, set up DDNS on the router and give friends the hostname.

## 9. Test

- **LAN**: Valheim → Join Game → Join IP → `<server-ip>:2456`.
- **Internet**: from a phone hotspot or a friend → Join IP → `<public-ip>:2456`,
  or join code with crossplay. UDP can't be tested from a browser; use a game client.
- **Server browser**: with `public = true` it appears after a few minutes.

---

## Deploying changes

Edit `~/my-valheim`, commit, then push the new system to the server:

```bash
cd ~/my-valheim
nix run nixpkgs#nixos-rebuild -- switch --flake .#valheim \
  --target-host admin@<server-ip> --sudo --ask-sudo-password
```

`switch` builds on the workstation, copies only the changed store paths, activates the
new system and restarts affected services. Valheim restarts only if its unit changed.

**Roll back**: `ssh admin@<server-ip> sudo nixos-rebuild switch --rollback`, or pick the
previous generation in the boot menu. Old generations are garbage-collected after 14 days.

## Updates

Three things update, on three schedules:

1. **NixOS (kernel, packages, this module).** Nothing changes on the server until you
   redeploy. `flake.lock` pins exact commits. Once a month, or when a security issue
   lands:

   ```bash
   cd ~/my-valheim
   nix flake update                    # newest nixpkgs on the release branch + newest valheim_nix
   git diff flake.lock
   nix run nixpkgs#nixos-rebuild -- build --flake .#valheim     # catches breakage without touching the server
   nix run nixpkgs#nixos-rebuild -- switch --flake .#valheim --target-host admin@<server-ip> --sudo --ask-sudo-password
   git commit -am "bump inputs"
   ```

   For a new NixOS release (e.g. 26.05 → 26.11), change the branch in `flake.nix`, read
   the release notes, then do the same. Leave `system.stateVersion` alone.

2. **The Valheim server.** The container checks Steam every 15 minutes and updates
   itself when nobody is online. Nothing to do.

3. **The container image.** With the default `:latest` tag, pull a newer one by hand:

   ```bash
   ssh admin@<server-ip> 'sudo podman pull ghcr.io/lloesche/valheim-server:latest && sudo systemctl restart podman-valheim'
   ```

   With a pinned digest, update `services.valheim.image` and redeploy.

## Health checks

```bash
systemctl status podman-valheim
sudo podman logs --tail 50 valheim
sensors                                           # sustained 90 °C+ under load: clean the fans
sudo smartctl -a /dev/sda | grep -Ei 'reallocated|pending|uncorrect'
```

Admins and bans: add SteamIDs (or PlayFab IDs for crossplay) to
`/var/lib/valheim/config/adminlist.txt` and `bannedlist.txt`, one per line.

---

## Backups (optional)

Two layers:

- **In the container** (always on): world zips in `/var/lib/valheim/config/backups/`
  every 2 h, kept 7 days. Same disk, so no help if the disk dies.
- **restic** (`backup.restic.enable`): encrypted snapshots of the whole `config/`
  directory (worlds, zips, admin/ban lists) to another machine or the cloud, every
  2 h at :30, with longer retention.

### Set up restic over SFTP

On the server, create root's SSH key and the repository password:

```bash
sudo ssh-keygen -t ed25519 -N '' -C root@valheim -f /root/.ssh/id_ed25519
sudo cat /root/.ssh/id_ed25519.pub
sudo sh -c 'umask 077; head -c 32 /dev/urandom | base64 > /var/lib/valheim/restic-password'
sudo cat /var/lib/valheim/restic-password     # SAVE THIS in a password manager
```

On the backup host, as the backup user, allow that key for SFTP only:

```bash
mkdir -p ~/backups/valheim
echo 'restrict,command="internal-sftp" ssh-ed25519 AAAA...server-key... root@valheim' >> ~/.ssh/authorized_keys
```

(`internal-sftp` needs `Subsystem sftp internal-sftp` in the backup host's `sshd_config`;
otherwise use the path to its `sftp-server` binary, e.g. `/usr/lib/openssh/sftp-server`.)

In `configuration.nix`, enable backups and pin the backup host's key
(`ssh-keyscan -t ed25519 <backup-host>`):

```nix
services.valheim.backup.restic = {
  enable = true;
  repository = "sftp:backup@<backup-host>:backups/valheim";
};
programs.ssh.knownHosts."<backup-host>".publicKey = "ssh-ed25519 AAAA...";
```

Deploy, then run the first backup by hand:

```bash
ssh admin@<server-ip> 'sudo systemctl start restic-backups-valheim && sudo restic-valheim snapshots'
```

For S3/B2 and other backends, set `repository` accordingly and put the credentials
in a root-only file referenced by `backup.restic.environmentFile`.

### Restore a world

```bash
ssh admin@<server-ip>
sudo restic-valheim snapshots                       # pick an ID, or use "latest"
sudo systemctl stop podman-valheim                  # never restore under a running server
sudo restic-valheim restore latest --target /tmp/restore --include /var/lib/valheim/config/worlds_local
sudo cp -a /tmp/restore/var/lib/valheim/config/worlds_local/. /var/lib/valheim/config/worlds_local/
sudo rm -rf /tmp/restore
sudo systemctl start podman-valheim
```

`restic-valheim` is a wrapper the NixOS module installs with the repository and password
already set; any restic subcommand works (`ls`, `diff`, `check`, `stats`).

To restore from a container zip instead: stop the server, unzip the chosen file from
`config/backups/` over `config/worlds_local/`, start it.

---

## Monitoring (optional)

See [monitoring/README.md](../monitoring/README.md) for the Prometheus, Loki and Grafana side.
On the server:

```nix
services.valheim.monitoring = {
  nodeExporter = { enable = true; allowedSources = [ "<prometheus-ip>" ]; };
  loki = { enable = true; url = "http://<loki-ip>:3100/loki/api/v1/push"; };
};
```

Verify after deploying:

```bash
# From the Prometheus host: metrics are served...
curl -s <server-ip>:9100/metrics | grep -c ^node_
# ...and from anywhere else: they time out.
curl -m 3 -s <server-ip>:9100/metrics || echo "refused: good"
# Logs reach Loki:
curl -s -G <loki-ip>:3100/loki/api/v1/query \
  --data-urlencode 'query=count_over_time({host="valheim"}[5m])'
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Container restarting in a loop | `journalctl -u podman-valheim -n 100`. Usually a missing `/var/lib/valheim/env`, or `SERVER_PASS` too short / inside `SERVER_NAME`. |
| Joinable on LAN, not from outside | Port forward to the right IP? WAN IP in `100.64.0.0/10` (CGNAT)? Try `crossplay`. |
| Not in the server browser | `public = true`? Give it 10 minutes. |
| Backups failing | `journalctl -u restic-backups-valheim -n 50`. Host key not in `knownHosts`, key not in `authorized_keys`, or password file missing. |
| Alloy not shipping | `systemctl status alloy`; its UI is on `127.0.0.1:12345` (`ssh -L 12345:127.0.0.1:12345 admin@<server-ip>`). |
| No live player count | Expected with `crossplay`: the server ignores Steam A2S queries. The dashboard uses the 10-minute log heartbeat instead. |
| Build fails on `environmentFile` / `passwordFile` | You gave a Nix path like `./env` or a `/nix/store` path. Use a quoted runtime path such as `"/var/lib/valheim/env"`. |
