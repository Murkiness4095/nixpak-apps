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

      appId = "com.tencent.WeChat";
      fonts = import ./lib/fonts.nix { inherit pkgs; };
      wxFonts = fonts.mk { name = "wechat-fonts-env"; };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = pkgs.wechat;
            flatpak.appId = appId;

            bubblewrap = {

              env = {
                GTK_THEME = "Adwaita:dark";
                GTK_APPLICATION_PREFER_DARK_THEME = "1";
                GTK_USE_PORTAL = "0"; # 使用沙盒内原生文件对话框，避免 portal 暴露宿主路径
                QT_QPA_PLATFORMTHEME = ""; # 禁用 xdgdesktopportal 主题，避免 Qt 走 portal 文件选择器
              };

              bind.dev = [
                "/dev/video0" # 摄像头（视频通话，可选删掉如果不用）
              ];

              bind.rw = with sloth; [

                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/.var/app/${appId}/xwechat"))
                  (sloth.concat' sloth.homeDir "/.xwechat")
                ]
                # 备用默认存储路径（若应用未设置存储位置）
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/.var/app/${appId}/xwechat_files"))
                  (sloth.concat' sloth.homeDir "/xwechat_files")
                ]

                # Downloads：与其它应用共享宿主真实 ~/Downloads
                xdgDownloadDir
              ];

              bind.ro = [
                (sloth.concat' sloth.xdgConfigHome "/kdeglobals")
                (sloth.concat' sloth.xdgConfigHome "/gtk-2-0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-3.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-4.0")
                (sloth.concat' sloth.xdgConfigHome "/fontconfig")
                (sloth.concat' sloth.xdgConfigHome "/dconf")
                [ "${wxFonts}/etc/fonts" "/etc/fonts" ]

                # 提供硬件信息和用户身份映射（防止沙箱内崩溃）
                "/sys/dev"
                "/sys/devices"
              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.wechat = pkgs.buildEnv {
        inherit (wrapped.config.script) name meta passthru;
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "WeChat";
            genericName = "WeChat";
            comment = "Tencent WeChat";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.wechat}/share/icons/hicolor/256x256/apps/wechat.png";
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
