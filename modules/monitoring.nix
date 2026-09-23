{ config, lib, ... }:
let
  cfg = config.services.valheim;
  mcfg = cfg.monitoring;
  inherit (lib) mkEnableOption mkOption types;

  alloyConfig = ''
    // Ship the systemd journal (OS units + the valheim container's stdout,
    // which podman writes under podman-valheim.service) to Loki.

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    loki.source.journal "journal" {
      max_age       = "12h"
      relabel_rules = loki.relabel.journal.rules
      labels        = { host = ${builtins.toJSON mcfg.loki.hostLabel}, job = "systemd-journal" }
      forward_to    = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = ${builtins.toJSON mcfg.loki.url}
      }
    }
  '';
in
{
  options.services.valheim.monitoring = {
    nodeExporter = {
      enable = mkEnableOption "Prometheus node_exporter (host metrics, systemd unit state and backup freshness)";

      port = mkOption {
        type = types.port;
        default = 9100;
        description = "node_exporter listen port.";
      };

      allowedSources = mkOption {
        # Validated because each entry is spliced into an iptables command.
        type = types.listOf (types.strMatching "[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[0-9]{1,2})?");
        default = [ ];
        example = [ "192.168.1.10" ];
        description = ''
          IPv4 addresses (or CIDRs) of the Prometheus servers allowed to scrape
          the exporter. Everything else is dropped by the firewall. Leave empty
          to keep the port closed (e.g. when scraping over a trusted Tailscale
          interface).
        '';
      };

      textfileDirectory = mkOption {
        type = types.str;
        default = "/var/lib/prometheus-node-exporter/textfile";
        description = "Directory for the textfile collector; the backup job writes its metrics here.";
      };
    };

    loki = {
      enable = mkEnableOption "shipping the systemd journal to Loki with Grafana Alloy";

      url = mkOption {
        type = types.str;
        example = "http://192.168.1.10:3100/loki/api/v1/push";
        description = "Loki push endpoint. Plain HTTP is only appropriate on a trusted LAN or VPN.";
      };

      hostLabel = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "Value of the `host` label on every log line. The bundled dashboard filters on it.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf mcfg.nodeExporter.enable {
      assertions = [
        {
          assertion = mcfg.nodeExporter.allowedSources == [ ] || !config.networking.nftables.enable;
          message = "services.valheim.monitoring.nodeExporter.allowedSources uses iptables rules; it does not support networking.nftables yet.";
        }
      ];

      services.prometheus.exporters.node = {
        enable = true;
        inherit (mcfg.nodeExporter) port;
        enabledCollectors = [ "systemd" ];
        extraFlags = [ "--collector.textfile.directory=${mcfg.nodeExporter.textfileDirectory}" ];
      };

      systemd.tmpfiles.rules = [
        "d ${mcfg.nodeExporter.textfileDirectory} 0755 root root -"
      ];

      # Plain iptables, not the exporter's openFirewall: that opens the port to
      # everyone, and ip46tables would reject an IPv4 -s address on the ip6tables
      # side, aborting the whole firewall reload.
      networking.firewall.extraCommands = lib.concatMapStrings (src: ''
        iptables -A nixos-fw -p tcp -m tcp --dport ${toString mcfg.nodeExporter.port} -s ${src} -m comment --comment node-exporter -j nixos-fw-accept
      '') mcfg.nodeExporter.allowedSources;
    })

    (lib.mkIf mcfg.loki.enable {
      # Config lives in /etc so `nixos-rebuild switch` reloads Alloy instead of restarting it.
      services.alloy = {
        enable = true;
        extraFlags = [
          "--server.http.listen-addr=127.0.0.1:12345" # debug UI, localhost only
          "--disable-reporting"                       # no usage stats to Grafana Labs
        ];
      };
      environment.etc."alloy/config.alloy".text = alloyConfig;
    })
  ]);
}
