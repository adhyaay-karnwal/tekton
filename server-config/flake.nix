{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;  # Required for Claude Code
    };
  in {
    # Host server configuration
    nixosConfigurations.nixos-server = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        { nixpkgs.pkgs = pkgs; }
        ./configuration.nix
      ];
    };

    # Agent container configuration (used by nixos-container create --flake)
    nixosConfigurations.agent = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        { nixpkgs.pkgs = pkgs; }
        ./agent-config.nix
      ];
    };
  };
}
