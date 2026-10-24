{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      mkNixPak = inputs.nixpak.lib.nixpak {
        inherit pkgs;
        inherit (pkgs) lib;
      };

      appId = "com.bytedance.feishu";
      fonts = import ./lib/fonts.nix { inherit pkgs; };

      # 飞书自带旧版 libfontconfig：用 minimal 模式（只写一份 fonts.conf，
      # 不 include nixpkgs conf.d）。字体定义见 lib/fonts.nix。
      feishuFonts = fonts.mk {
        name = "feishu-fonts-env";
        minimal = true;
      };

      # 飞书会以安装目录为 cwd，导致文件选择器默认落在 /nix/store/...。
      # 外面套一层 wrapper，先把 cwd 切到 ~/Downloads 再执行原 wrapper。
      feishuLauncher = pkgs.runCommandLocal "feishu-launcher" { } ''
        mkdir -p $out/bin
        cat > $out/bin/bytedance-feishu <<EOF
        #!${pkgs.runtimeShell}
        cd "\$HOME/Downloads" 2>/dev/null || cd "\$HOME"
        exec ${pkgs.feishu}/bin/bytedance-feishu "\$@"
        EOF
        chmod +x $out/bin/bytedance-feishu
      '';

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = feishuLauncher;
            app.binPath = "bin/bytedance-feishu";

            flatpak.appId = appId;

            bubblewrap = {

              env = {
              };

              bind.dev = [
                "/dev/video0"
              ];

              bind.rw = with sloth; [
                xdgDownloadDir
              ];

              bind.ro = [

                (sloth.concat' sloth.xdgConfigHome "/kdeglobals")
                (sloth.concat' sloth.xdgConfigHome "/gtk-2.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-3.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-4.0")
                (sloth.concat' sloth.xdgConfigHome "/dconf")
                [ "${feishuFonts}/etc/fonts" "/etc/fonts" ]
              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.feishu = pkgs.buildEnv {
        inherit (wrapped.config.script) name meta passthru;
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "Feishu";
            genericName = "Feishu";
            comment = "ByteDance Feishu";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.feishu}/share/icons/hicolor/256x256/apps/bytedance-feishu.png";
            type = "Application";
            categories = [
              "InstantMessaging"
              "Network"
            ];
            extraConfig = {
              X-Flatpak = appId;
            };
          })
        ];
      };
    };
}
