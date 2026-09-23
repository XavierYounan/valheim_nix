{ config, lib, pkgs, ... }:
{
  # ---------------------------------------------------------------- base ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Lets `nixos-rebuild --target-host` push unsigned store paths from your
  # workstation. Anyone in this list is effectively root.
  nix.settings.trusted-users = [ "root" "admin" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Set once at install time and leave alone; read the NixOS release notes before changing it.
  system.stateVersion = "26.05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "UTC"; # e.g. "Europe/Oslo"
  i18n.defaultLocale = "en_US.UTF-8";

  hardware.enableRedistributableFirmware = true;
  zramSwap.enable = true;

  # Automatic security patches between your own rebuilds are not possible
  # without a reachable git remote; see "Updates" in the runbook.

  # ------------------------------------------------- headless laptop (opt) ---
  # Uncomment when the server is an old laptop: never sleep, ignore the lid.
  # services.logind.settings.Login = {
  #   HandleLidSwitch = "ignore";
  #   HandleLidSwitchExternalPower = "ignore";
  #   HandleLidSwitchDocked = "ignore";
  # };
  # systemd.targets = {
  #   sleep.enable = false;
  #   suspend.enable = false;
  #   hibernate.enable = false;
  #   hybrid-sleep.enable = false;
  # };

  # ------------------------------------------------------------ network ---
  networking.hostName = "valheim";
  # DHCP by default. Give the machine a DHCP reservation on the router so the
  # port forward has a stable target.

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "admin" ];
    };
  };
  # Bans IPs that hammer SSH. Harmless with key-only auth, cuts log noise.
  services.fail2ban.enable = true;

  # Optional: admin access from anywhere without exposing SSH to the internet.
  # After first boot: `sudo tailscale up`. Then consider dropping 22 from
  # allowedTCPPorts above and relying on the trusted interface instead.
  # services.tailscale.enable = true;
  # networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # -------------------------------------------------------------- users ---
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # Required: password SSH is off, so without a key you are locked out.
      # "ssh-ed25519 AAAA... you@workstation"
    ];
  };
  # sudo asks for the password you set with `passwd` after install; deploy
  # with `nixos-rebuild ... --sudo --ask-sudo-password`. Setting this to false
  # is more convenient but means a stolen SSH key is instant root.
  security.sudo.wheelNeedsPassword = true;

  # ------------------------------------------------------------ valheim ---
  services.valheim = {
    enable = true;
    openFirewall = true; # UDP 2456-2457; also port-forward these on the router
    public = false;      # true = listed in the Steam / in-game browser
    crossplay = true;    # join codes for consoles / Game Pass, works behind CGNAT
    # Pin the image for reproducible deploys (`podman image inspect` shows the digest):
    # image = "ghcr.io/lloesche/valheim-server@sha256:...";
  };

  # ------------------------------------------------------ backups (opt) ---
  # services.valheim.backup.restic = {
  #   enable = true;
  #   repository = "sftp:backup@192.168.1.10:backups/valheim";
  # };
  # # Pin the backup host's key so root's first SFTP connection can't be MITM'd
  # # or stall on a prompt. Get it with `ssh-keyscan -t ed25519 192.168.1.10`.
  # programs.ssh.knownHosts."192.168.1.10".publicKey = "ssh-ed25519 AAAA...";

  # --------------------------------------------------- monitoring (opt) ---
  # services.valheim.monitoring = {
  #   nodeExporter = {
  #     enable = true;
  #     allowedSources = [ "192.168.1.10" ]; # your Prometheus
  #   };
  #   loki = {
  #     enable = true;
  #     url = "http://192.168.1.10:3100/loki/api/v1/push";
  #   };
  # };

  # ------------------------------------------------------------- tools ---
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    lm_sensors
    smartmontools
    dig
  ];
}
