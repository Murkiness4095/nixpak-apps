{
  description = "nixpak-sandboxed apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpak.url = "github:nixpak/nixpak";
    nixpak.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, ... }@inputs:
    let
      nixpakOverlay = final: prev:
        if final.stdenv.hostPlatform.isLinux
        then { nixpakApps = self.packages.${final.stdenv.hostPlatform.system}; }
        else { nixpakApps = { }; };

      nixpakNixosModule = { pkgs, lib, ... }: {
        environment.systemPackages = lib.optionals pkgs.stdenv.hostPlatform.isLinux
          (builtins.attrValues self.packages.${pkgs.stdenv.hostPlatform.system});
      };

      nixpakHomeModule = { pkgs, lib, ... }: {
        home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux
          (builtins.attrValues self.packages.${pkgs.stdenv.hostPlatform.system});
      };
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imports = [
        ./wechat.nix
        ./qq.nix
        ./dingtalk.nix
        ./unwrapped/dingtalk.nix
        ./feishu.nix
        ./telegram.nix
        ./nheko.nix
        ./vesktop.nix
        ./wechat-uos.nix
        ./heroic.nix
        ./bottles.nix
      ];

      flake = {
        overlays.default = nixpakOverlay;
        nixosModules.default = nixpakNixosModule;
        homeManagerModules.default = nixpakHomeModule;

        lib.nixpak = {
          common = ./common.nix;
          fonts = ./lib/fonts.nix;
        };
      };
    };
}
