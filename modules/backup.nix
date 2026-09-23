{ config, lib, pkgs, ... }:
let
  cfg = config.services.valheim;
  bcfg = cfg.backup.restic;
  inherit (lib) mkEnableOption mkOption types;

  textfileDir = config.services.valheim.monitoring.nodeExporter.textfileDirectory;
  exportMetrics = cfg.monitoring.nodeExporter.enable;
in
{
  options.services.valheim.backup.restic = {
    enable = mkEnableOption "encrypted, deduplicated off-box restic snapshots of the Valheim config directory";

    repository = mkOption {
      type = types.str;
      example = "sftp:backup@nas.lan:backups/valheim";
      description = ''
        restic repository URL. For SFTP, root's SSH key (`/root/.ssh/id_ed25519`)
        is used and the host must be in `programs.ssh.knownHosts` so the first
        connection does not stall on a prompt.
      '';
    };

    passwordFile = mkOption {
      type = types.str;
      default = "${cfg.dataDir}/restic-password";
      defaultText = lib.literalExpression ''"''${config.services.valheim.dataDir}/restic-password"'';
      description = "Runtime file with the repository password. Lose it and the backups are unreadable: keep a copy in a password manager.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/lib/valheim/restic-env";
      description = "Optional runtime file with credentials for cloud backends (e.g. `AWS_ACCESS_KEY_ID`, `B2_ACCOUNT_KEY`).";
    };

    schedule = mkOption {
      type = types.str;
      default = "00/2:30";
      description = "systemd OnCalendar expression. The default runs 30 min after each of the container's 2-hourly world zips.";
    };

    pruneOpts = mkOption {
      type = types.listOf types.str;
      default = [
        "--keep-hourly 24"
        "--keep-daily 14"
        "--keep-weekly 8"
        "--keep-monthly 12"
      ];
      description = "`restic forget` retention flags.";
    };

    checkOpts = mkOption {
      type = types.listOf types.str;
      default = [ "--read-data-subset=10%" ];
      description = "`restic check` flags, run after every backup.";
    };
  };

  config = lib.mkIf (cfg.enable && bcfg.enable) {
    assertions = [
      {
        assertion = !(lib.hasPrefix builtins.storeDir bcfg.passwordFile);
        message = "services.valheim.backup.restic.passwordFile must be a runtime path, not a file in the Nix store.";
      }
      {
        assertion = bcfg.environmentFile == null || !(lib.hasPrefix builtins.storeDir bcfg.environmentFile);
        message = "services.valheim.backup.restic.environmentFile must be a runtime path, not a file in the Nix store.";
      }
    ];

    services.restic.backups.valheim = {
      inherit (bcfg) repository passwordFile environmentFile pruneOpts checkOpts;
      paths = [ "${cfg.dataDir}/config" ];
      exclude = [ "${cfg.dataDir}/config/cache" ];
      initialize = true; # creates the repo on first run
      timerConfig = {
        OnCalendar = bcfg.schedule;
        Persistent = true; # catch up after a reboot
      };
      runCheck = true;
      # Runs after every attempt (success or not) with $SERVICE_RESULT set, and
      # publishes backup freshness through node_exporter's textfile collector.
      backupCleanupCommand = lib.mkIf exportMetrics ''
        export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep ]}:$PATH
        out=${textfileDir}/valheim_backup.prom
        now=$(date +%s)
        prev=$(grep -s '^valheim_backup_last_success_timestamp_seconds ' "$out" | cut -d' ' -f2)
        if [ "$SERVICE_RESULT" = "success" ]; then
          result=1; success=$now
        else
          result=0; success=''${prev:-0}
        fi
        {
          echo "# HELP valheim_backup_last_run_timestamp_seconds Unix time of the last restic attempt."
          echo "# TYPE valheim_backup_last_run_timestamp_seconds gauge"
          echo "valheim_backup_last_run_timestamp_seconds $now"
          echo "# HELP valheim_backup_last_success_timestamp_seconds Unix time of the last successful restic backup."
          echo "# TYPE valheim_backup_last_success_timestamp_seconds gauge"
          echo "valheim_backup_last_success_timestamp_seconds $success"
          echo "# HELP valheim_backup_last_result 1 if the last restic attempt succeeded, else 0."
          echo "# TYPE valheim_backup_last_result gauge"
          echo "valheim_backup_last_result $result"
        } > "$out.tmp" && mv "$out.tmp" "$out"
      '';
    };
  };
}
