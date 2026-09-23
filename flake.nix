{
  description = "Declarative Valheim dedicated server for NixOS, with optional restic backups and Prometheus/Loki monitoring";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosModules.default = import ./modules;
      nixosModules.valheim = self.nixosModules.default;

      # `nix flake init -t github:XavierYounan/valheim_nix` scaffolds a private host flake.
      templates.default = {
        path = ./templates/host;
        description = "A host flake that runs the Valheim module (add your own hardware-configuration.nix)";
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;

      # Smoke test with every option switched on (`nix flake check` builds it). The dummy
      # filesystem and bootloader stand in for a real hardware-configuration.nix.
      nixosConfigurations.ci = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          {
            system.stateVersion = "26.05";
            boot.loader.grub.devices = [ "nodev" ];
            fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };

            services.valheim = {
              enable = true;
              openFirewall = true;
              crossplay = true;
              backup.restic = {
                enable = true;
                repository = "sftp:backup@192.0.2.10:backups/valheim";
              };
              monitoring = {
                nodeExporter = {
                  enable = true;
                  allowedSources = [ "192.0.2.10" ];
                };
                loki = {
                  enable = true;
                  url = "http://192.0.2.10:3100/loki/api/v1/push";
                };
              };
            };
          }
        ];
      };

      checks.${system}.ci = self.nixosConfigurations.ci.config.system.build.toplevel;
    };
}
