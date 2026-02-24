# NixOS configuration for Stablecoin preview containers (Elixir/Phoenix API + React SPA)
# This file lives in the stablecoin repo and is fetched by tekton at preview-create time.
# Built by: tekton's preview.sh using nix build --impure --expr
#
# system.build.previewMeta  — read by tekton before container start (routing, services, DB)
# environment.etc."preview-meta.json"  — same JSON available inside the running container
{ config, lib, pkgs, ... }:

let
  erlang = pkgs.erlang_27;
  beamPackages = pkgs.beam.packagesWith erlang;
  elixir = beamPackages.elixir_1_18;

  meta = {
    setupService = "setup-stablecoin";
    appServices  = [ "stablecoin-backend" "stablecoin-frontend" ];
    database     = "container";
    routes       = [
      { path = "/api/*"; port = 4000; }
      { path = "/";      port = 3000; }
    ];
    hostSecrets  = [];
    extraHosts   = [];
  };
in
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

  # Open ports: 3000 (React frontend), 4000 (Phoenix backend)
  networking.firewall.allowedTCPPorts = [ 3000 4000 ];

  # PostgreSQL (runs inside the container for isolation)
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "stablecoin" ];
    ensureUsers = [{
      name = "stablecoin";
      ensureDBOwnership = true;
    }];
    authentication = lib.mkForce ''
      local all all trust
      host all all 127.0.0.1/32 trust
      host all all ::1/128 trust
    '';
  };

  # Setup stablecoin: clone repo, build backend + frontend, run migrations
  systemd.services.setup-stablecoin = {
    description = "Setup Stablecoin preview (clone, build, migrate)";
    after = [ "systemd-resolved.service" "postgresql.service" ];
    wants = [ "systemd-resolved.service" "postgresql.service" ];
    before = [ "stablecoin-backend.service" "stablecoin-frontend.service" ];
    path = [
      pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused
      pkgs.git erlang elixir pkgs.nodejs_22 pkgs.gcc pkgs.gnumake pkgs.openssl
      pkgs.postgresql  # for pg_isready DB readiness check
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "preview";
      WorkingDirectory = "/home/preview";
      TimeoutStartSec = "900";  # 15 minutes — Elixir compilation is slow
    };
    script = ''
      set -euo pipefail

      # Load environment first — provides PREVIEW_HOST for secrets generation
      if [ ! -f /etc/preview.env ]; then
        echo "ERROR: /etc/preview.env not found"
        exit 1
      fi
      set -a
      source /etc/preview.env
      set +a

      SECRETS_FILE="/home/preview/.stablecoin-secrets.env"

      # Generate stable secrets on first run (persist across restarts)
      if [ ! -f "$SECRETS_FILE" ]; then
        echo "Generating preview secrets..."
        {
          echo "DATABASE_URL=postgresql://stablecoin@localhost/stablecoin"
          echo "SECRET_KEY_BASE=$(${pkgs.openssl}/bin/openssl rand -base64 64 | tr -d '\n')"
          echo "JWT_SECRET_KEY=$(${pkgs.openssl}/bin/openssl rand -base64 32 | tr -d '\n')"
          echo "PHX_SERVER=true"
          echo "PORT=4000"
          echo "PHX_HOST=''${PREVIEW_HOST}"
        } > "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
      fi

      # Load generated secrets; preview.env re-sourced so its values take precedence
      set -a
      source "$SECRETS_FILE"
      source /etc/preview.env
      set +a

      APP_DIR="/home/preview/app"

      # On container restart, skip setup entirely if the app is already built.
      # Explicit rebuilds go through 'preview update' which clears the marker.
      if [ -d "$APP_DIR/.git" ] && [ -f "$APP_DIR/api/_build/prod/rel/stablecoin_ops/bin/stablecoin_ops" ] && [ ! -f /tmp/force-rebuild ]; then
        echo "App already built, skipping setup (container restart)."
        exit 0
      fi
      rm -f /tmp/force-rebuild

      # Build authenticated URL from the root-only token file
      PREVIEW_TOKEN=$(cat /etc/preview-token 2>/dev/null || echo "")
      AUTHED_URL=$(echo "$PREVIEW_REPO_URL" | sed "s|https://|https://x-access-token:$PREVIEW_TOKEN@|")

      if [ -d "$APP_DIR/.git" ]; then
        echo "Updating existing repo..."
        ${pkgs.git}/bin/git -C "$APP_DIR" remote set-url origin "$AUTHED_URL"
        ${pkgs.git}/bin/git -C "$APP_DIR" fetch origin
        ${pkgs.git}/bin/git -C "$APP_DIR" reset --hard "origin/$PREVIEW_BRANCH"
      else
        echo "Cloning $PREVIEW_REPO_URL (branch: $PREVIEW_BRANCH)..."
        ${pkgs.git}/bin/git clone --depth 1 --branch "$PREVIEW_BRANCH" --single-branch "$AUTHED_URL" "$APP_DIR"
        cd "$APP_DIR"
      fi

      # ── Backend build ──────────────────────────────────────────────────
      echo "Building Elixir backend..."
      cd "$APP_DIR/api"

      export MIX_ENV=prod
      export HEX_HTTP_TIMEOUT=120

      ${elixir}/bin/mix local.hex --force
      ${elixir}/bin/mix local.rebar --force
      ${elixir}/bin/mix deps.get --only prod
      ${elixir}/bin/mix compile
      ${elixir}/bin/mix release stablecoin_ops --overwrite

      # Verify the release binary exists with the expected name.
      # If mix.exs declares a different release name, fail fast with a clear error.
      if [ ! -f "$APP_DIR/api/_build/prod/rel/stablecoin_ops/bin/stablecoin_ops" ]; then
        echo "ERROR: release binary not found at api/_build/prod/rel/stablecoin_ops/bin/stablecoin_ops"
        echo "Check that mix.exs declares: releases: [stablecoin_ops: [...]]"
        exit 1
      fi

      echo "Backend build complete."

      # ── Database migrations ────────────────────────────────────────────
      # Wait for PostgreSQL to accept connections before running migrations.
      # systemd `wants` doesn't guarantee readiness, only that the unit started.
      echo "Waiting for PostgreSQL to be ready..."
      for i in $(seq 1 30); do
        ${pkgs.postgresql}/bin/pg_isready -U stablecoin -d stablecoin -q && break
        echo "  attempt $i/30 — not ready yet, waiting 2s..."
        sleep 2
      done
      ${pkgs.postgresql}/bin/pg_isready -U stablecoin -d stablecoin || {
        echo "ERROR: PostgreSQL not ready after 60s"
        exit 1
      }

      # Uses Ecto.Migrator.with_repo since the app has no Release module.
      echo "Running database migrations..."
      cd "$APP_DIR"
      ./api/_build/prod/rel/stablecoin_ops/bin/stablecoin_ops eval \
        "{:ok, _} = Ecto.Migrator.with_repo(StablecoinOps.Repo, &Ecto.Migrator.run(&1, :up, all: true))"

      # Seed blockchain networks (idempotent — safe to re-run)
      echo "Seeding network data..."
      ./api/_build/prod/rel/stablecoin_ops/bin/stablecoin_ops eval "
        {:ok, _} = Ecto.Migrator.with_repo(StablecoinOps.Repo, fn _repo ->
          networks = [
            %{name: \"Ethereum\", chain_id: 1, rpc_url: \"https://eth.drpc.org\", explorer_api_url: \"https://api.etherscan.io/api\"},
            %{name: \"Sepolia\", chain_id: 11155111, rpc_url: \"https://sepolia.drpc.org\", explorer_api_url: \"https://api-sepolia.etherscan.io/api\"},
            %{name: \"Arbitrum One\", chain_id: 42161, rpc_url: \"https://arbitrum.drpc.org\", explorer_api_url: \"https://api.arbiscan.io/api\"},
            %{name: \"Arbitrum Sepolia\", chain_id: 421614, rpc_url: \"https://sepolia-rollup.arbitrum.io/rpc\", explorer_api_url: \"https://api-sepolia.arbiscan.io/api\"},
            %{name: \"Polygon\", chain_id: 137, rpc_url: \"https://polygon.drpc.org\", explorer_api_url: \"https://api.polygonscan.com/api\"},
            %{name: \"Optimism\", chain_id: 10, rpc_url: \"https://optimism.drpc.org\", explorer_api_url: \"https://api-optimistic.etherscan.io/api\"}
          ]
          Enum.each(networks, fn network ->
            case StablecoinOps.Repo.get_by(StablecoinOps.Networks.Network, chain_id: network.chain_id) do
              nil -> StablecoinOps.Networks.create_network(network)
              existing -> StablecoinOps.Networks.update_network(existing, network)
            end
          end)
        end)" || echo "Seeding skipped or not available."

      # ── Frontend build ─────────────────────────────────────────────────
      echo "Building React frontend..."
      cd "$APP_DIR/frontend"

      ${pkgs.nodejs_22}/bin/npm ci
      ${pkgs.nodejs_22}/bin/npm run build

      echo "Frontend build complete."

      echo "Stablecoin setup complete."
    '';
  };

  # Stablecoin backend: Phoenix server on port 4000
  systemd.services.stablecoin-backend = {
    description = "Stablecoin Phoenix backend";
    after = [ "setup-stablecoin.service" "postgresql.service" ];
    requires = [ "setup-stablecoin.service" ];
    wants = [ "postgresql.service" ];
    path = [ pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "simple";
      User = "preview";
      WorkingDirectory = "/home/preview/app";
      # Secrets file loaded first; /etc/preview.env overrides any key present in both
      EnvironmentFile = [ "/home/preview/.stablecoin-secrets.env" "/etc/preview.env" ];
      ExecStart = "/home/preview/app/api/_build/prod/rel/stablecoin_ops/bin/stablecoin_ops start";
      Restart = "on-failure";
      RestartSec = 5;
      MemoryMax = "2G";
      CPUQuota = "200%";
    };
  };

  # Stablecoin frontend: React SPA on port 3000
  systemd.services.stablecoin-frontend = {
    description = "Stablecoin React frontend (port 3000)";
    after = [ "setup-stablecoin.service" ];
    requires = [ "setup-stablecoin.service" ];
    path = [ pkgs.bash pkgs.coreutils pkgs.static-web-server ];
    serviceConfig = {
      Type = "simple";
      User = "preview";
      WorkingDirectory = "/home/preview/app/frontend";
      ExecStart = "${pkgs.static-web-server}/bin/static-web-server --port 3000 --root dist --page-fallback dist/index.html";
      Restart = "on-failure";
      RestartSec = 5;
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
  };

  system.build.previewMeta = pkgs.writeText "preview-meta.json" (builtins.toJSON meta);
  environment.etc."preview-meta.json".text = builtins.toJSON meta;

  # Packages available in stablecoin preview containers
  environment.systemPackages = with pkgs; [
    git
    erlang
    elixir
    nodejs_22
    gcc
    gnumake
    openssl
    curl
    jq
    gh
    static-web-server  # Static file server for the React SPA
  ];

  system.stateVersion = "24.11";
}
