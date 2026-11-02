{
  description = "nixpak-sandboxed apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpak.url = "github:nixpak/nixpak";
    nixpak.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
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

      # 消费者直接引用包，不走 overlay（overlay 会和 nixpkgs 本身形成循环）：
      #   inputs.nixpak-apps.packages.${pkgs.stdenv.hostPlatform.system}.wechat
      # 或用 let 绑定别名：
      #   let nixpakApps = inputs.nixpak-apps.packages.${pkgs.stdenv.hostPlatform.system}; in ...
      # 自定义沙盒应用可复用 common / 字体模块：
      flake.lib.nixpak = {
        common = ./common.nix;
        fonts = ./lib/fonts.nix;
      };
    };
}
