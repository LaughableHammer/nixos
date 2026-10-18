{


  inputs = {
    # Pinned to the revision Hyprland 8010b4e was built against, so Hyprland
    # stays prebuilt and mesa stays in lockstep (see hyprland input below).
    nixpkgs.url = "github:nixos/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0";
    # Separate pin for llama.cpp so its (uncached) ROCm build stays cached and
    # can be bumped independently of the rest of the system.
    nixpkgs-llama.url = "github:NixOS/nixpkgs/7a0f122f5090cf4c2ade2a13a0e229d4e19ba71f";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned so `nix flake update` cannot move them unexpectedly.
    noctalia = {
      url = "github:noctalia-dev/noctalia/e37d7145b95a51b801db9bb20d1c600f35111e0b";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland/8010b4e5c66f97aa82cd5b3332b4ec613779b9a7";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # GDB plugin for binary exploitation.
    pwndbg = {
      url = "github:pwndbg/pwndbg";
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, nix-gaming, ... }:
    let
      userName = "laughablehammer";
      mkHost =
        hostName:
        let
          hostPath = ./hosts + "/${hostName}";
        in
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs hostName userName; };
          modules = [
            ./configuration.nix
            hostPath
            { networking.hostName = hostName; }
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs hostName userName; };
              home-manager.users.${userName} = {
                imports = [
                  ./home.nix
                  (hostPath + "/home.nix")
                ];
              };
            }
          ];
        };
    in
    {
      packages.x86_64-linux = {
        inherit (nix-gaming.packages.x86_64-linux) rocket-league;
      };

      nixosConfigurations = {
        hammernix = mkHost "hammernix";
      };
    };
}
