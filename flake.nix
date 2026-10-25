{
  description = "nixpak-sandboxed WeChat";

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
        ./wechat-uos.nix
        ./vesktop.nix
      ];
    };
}
