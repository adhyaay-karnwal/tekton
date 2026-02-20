# NixOS configuration for imperative nspawn preview containers
# Built via: nix build /etc/nixos#nixosConfigurations.preview.config.system.build.toplevel
# Used by: nixos-container create <name> --system-path <closure>
#
# Environment flow:
# 1. `preview create` writes /etc/preview.env into the container filesystem
# 2. setup-preview reads it to clone repo, install deps, build
# 3. preview-app reads it to run the app with correct DATABASE_URL, PORT, etc.
{ config, lib, pkgs, ... }:
{
  boot.isContainer = true;

  # Networking — static IP is set by nixos-container, disable DHCP
  networking.useDHCP = false;
  networking.useHostResolvConf = false;
  services.resolved = {
    enable = true;
    settings.Resolve.FallbackDNS = [ "8.8.8.8" "1.1.1.1" ];
  };
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];

  # Open port 3000 for the preview app
  networking.firewall.allowedTCPPorts = [ 3000 ];

  # Setup preview: clone repo, install deps, build
  systemd.services.setup-preview = {
    description = "Setup preview deployment (clone, install, build)";
    # Not started at boot — triggered from host after container is up
    after = [ "systemd-resolved.service" ];
    wants = [ "systemd-resolved.service" ];
    before = [ "preview-app.service" ];
    path = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.nodejs_22 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "preview";
      WorkingDirectory = "/home/preview";
    };
    script = ''
      set -euo pipefail

      # Load environment
      if [ ! -f /etc/preview.env ]; then
        echo "ERROR: /etc/preview.env not found"
        exit 1
      fi
      set -a
      source /etc/preview.env
      set +a

      APP_DIR="/home/preview/app"

      # On container restart, skip setup if the app is already built.
      # This avoids git fetch with expired GitHub App tokens.
      # Explicit rebuilds go through 'preview update' which clears the marker.
      if [ -d "$APP_DIR/node_modules" ] && [ ! -f /tmp/force-rebuild ]; then
        echo "App already built, skipping setup (container restart)."
        exit 0
      fi
      rm -f /tmp/force-rebuild

      if [ -d "$APP_DIR/.git" ]; then
        # Update: fetch and reset to latest
        echo "Updating existing repo..."
        cd "$APP_DIR"
        ${pkgs.git}/bin/git fetch origin
        ${pkgs.git}/bin/git reset --hard "origin/$PREVIEW_BRANCH"
      else
        # Fresh clone
        echo "Cloning $PREVIEW_REPO_URL (branch: $PREVIEW_BRANCH)..."
        ${pkgs.git}/bin/git clone --branch "$PREVIEW_BRANCH" --single-branch "$PREVIEW_REPO_URL" "$APP_DIR"
        cd "$APP_DIR"
      fi

      # Install dependencies
      if [ -f package-lock.json ]; then
        echo "Installing dependencies (npm ci)..."
        ${pkgs.nodejs_22}/bin/npm ci
      else
        echo "No lockfile found, installing dependencies (npm install)..."
        ${pkgs.nodejs_22}/bin/npm install
      fi

      # Build
      echo "Building application..."
      ${pkgs.nodejs_22}/bin/npm run build

      echo "Setup complete."
    '';
  };

  # Preview app: run the built application
  systemd.services.preview-app = {
    description = "Preview application";
    # Not started at boot — triggered from host after container is up
    after = [ "setup-preview.service" ];
    requires = [ "setup-preview.service" ];
    path = [ pkgs.bash pkgs.coreutils pkgs.nodejs_22 ];
    serviceConfig = {
      Type = "simple";
      User = "preview";
      WorkingDirectory = "/home/preview/app";
      EnvironmentFile = "/etc/preview.env";
      ExecStart = "${pkgs.nodejs_22}/bin/npm start";
      Restart = "on-failure";
      RestartSec = 5;
      MemoryMax = "1G";
      CPUQuota = "100%";
    };
  };

  # Preview user (non-root)
  users.users.preview = {
    isNormalUser = true;
    home = "/home/preview";
    shell = pkgs.bash;
  };

  # SSH access for debugging
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.root = {
    password = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... your-key-here"
    ];
  };

  # Packages available in preview containers
  environment.systemPackages = with pkgs; [
    git
    nodejs_22
    curl
    jq
    gh
  ];

  system.stateVersion = "24.11";
}
