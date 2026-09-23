{ config, lib, ... }:
let
  cfg = config.services.valheim;
  inherit (lib) mkEnableOption mkOption types;

  # Secrets must be read at runtime, never copied into the world-readable /nix/store.
  notInStore = path: !(lib.hasPrefix builtins.storeDir path);
in
{
  options.services.valheim = {
    enable = mkEnableOption "a Valheim dedicated server in a Podman container";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/lloesche/valheim-server:latest";
      example = "ghcr.io/lloesche/valheim-server@sha256:<digest>";
      description = ''
        Container image. Pin it by digest to control exactly what runs; the
        game server itself still self-updates from Steam (see `updateCron`).
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/valheim";
      description = "State directory. Worlds and the container's own backups live in `config/`, the server install in `data/`.";
    };

    environmentFile = mkOption {
      type = types.str;
      default = "${cfg.dataDir}/env";
      defaultText = lib.literalExpression ''"''${config.services.valheim.dataDir}/env"'';
      description = ''
        Runtime file holding `SERVER_NAME`, `WORLD_NAME` and `SERVER_PASS`
        (see `env.example`). A string path on purpose: it is read by Podman
        at start-up and never enters the Nix store. Keep it `chmod 600`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 2456;
      description = "First UDP game port. The server also uses `port + 1`.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open UDP `port` and `port + 1` in the NixOS firewall.";
    };

    public = mkOption {
      type = types.bool;
      default = false;
      description = "List the server in the Steam and in-game server browsers. The password is required either way.";
    };

    crossplay = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Start with `-crossplay`: players join with a PlayFab join code, which
        works for Xbox/PC Game Pass and relays through CGNAT. The server then
        stops answering Steam A2S queries, so there is no live player count.
      '';
    };

    timeZone = mkOption {
      type = types.str;
      default = if config.time.timeZone != null then config.time.timeZone else "UTC";
      defaultText = lib.literalExpression ''config.time.timeZone or "UTC"'';
      description = "Time zone for the container's cron schedules and log timestamps.";
    };

    updateCron = mkOption {
      type = types.str;
      default = "*/15 * * * *";
      description = "How often the container checks Steam for a server update (restarts only when one is found and nobody is online).";
    };

    worldBackups = {
      cron = mkOption {
        type = types.str;
        default = "0 */2 * * *";
        description = "Schedule for the container's own world zips in `config/backups/`.";
      };
      maxAgeDays = mkOption {
        type = types.ints.positive;
        default = 7;
        description = "Days to keep the container's world zips.";
      };
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { ADMINLIST_IDS = "76561198000000000"; };
      description = ''
        Extra non-secret variables for the image (see its README). Values end
        up in the Nix store; put secrets in `environmentFile` instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = notInStore cfg.environmentFile;
        message = "services.valheim.environmentFile must be a runtime path (e.g. /var/lib/valheim/env), not a file in the Nix store: it holds SERVER_PASS.";
      }
    ];

    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers.valheim = {
        inherit (cfg) image;
        autoStart = true;
        ports = [ "${toString cfg.port}-${toString (cfg.port + 1)}:${toString cfg.port}-${toString (cfg.port + 1)}/udp" ];
        volumes = [
          "${cfg.dataDir}/config:/config"    # worlds, backups, admin/ban lists
          "${cfg.dataDir}/data:/opt/valheim" # the server install itself (~1 GB)
        ];
        environment = {
          TZ = cfg.timeZone;
          SERVER_PORT = toString cfg.port;
          SERVER_PUBLIC = if cfg.public then "1" else "0";
          BACKUPS = "true";
          BACKUPS_CRON = cfg.worldBackups.cron;
          BACKUPS_MAX_AGE = toString cfg.worldBackups.maxAgeDays;
          UPDATE_CRON = cfg.updateCron;
        }
        // lib.optionalAttrs cfg.crossplay { SERVER_ARGS = "-crossplay"; }
        // cfg.extraEnvironment;
        environmentFiles = [ cfg.environmentFile ];
        extraOptions = [
          "--cap-add=sys_nice" # lets the server raise its own priority
          "--stop-timeout=120" # give it time to save the world on shutdown
        ];
      };
    };

    # Survive slow networks and power-loss reboots: wait for the network, and
    # never give up retrying (the default 5-tries-then-stop can leave it dead).
    systemd.services.podman-valheim = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = lib.mkForce "15s";
      };
    };

    # 0700 on the top level: the env file and restic password live here.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}        0700 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/data   0755 root root -"
    ];

    networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ cfg.port (cfg.port + 1) ];
  };
}
