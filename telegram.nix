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

      appId = "org.telegram.desktop";

      telegramLauncher = pkgs.runCommandLocal "telegram-launcher" { } ''
        mkdir -p $out/bin
        cat > $out/bin/telegram <<EOF
        #!${pkgs.runtimeShell}
        ${pkgs.coreutils}/bin/sleep 2147483647 & s1=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s2=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s3=\$!
        ${pkgs.telegram-desktop}/bin/Telegram "\$@" & app=\$!
        wait \$app
        rc=\$?
        kill \$s1 \$s2 \$s3 2>/dev/null
        exit \$rc
        EOF
        chmod +x $out/bin/telegram
      '';

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = telegramLauncher;
            app.binPath = "bin/telegram";

            flatpak.appId = appId;
            dbus.policies."org.freedesktop.StatusNotifierItem-6-1" = "own";

            bubblewrap = {

              env = {
              };

              bind.dev = [
                "/dev/video0"
              ];

              bind.rw = with sloth; [
                # 数据走 common 的 ~/.var/app/org.telegram.desktop；Downloads 共享宿主
                xdgDownloadDir
              ];

              bind.ro = [
                # fcitx5-qt 的客户端候选框会读沙盒内 ~/.config/fcitx5 和主题目录；
                # 不绑的话 Qt 应用会回退到 default 灰色主题
                [
                  (sloth.concat' sloth.homeDir "/.config/fcitx5")
                  (sloth.concat' sloth.xdgConfigHome "/fcitx5")
                ]
                [
                  (sloth.concat' sloth.homeDir "/.local/share/fcitx5/themes")
                  (sloth.concat' sloth.xdgDataHome "/fcitx5/themes")
                ]
                # Telegram 不自带字体，也不再用自定义字体集；必须给宿主系统字体
                "/etc/fonts"
                "/run/current-system/sw/share/fonts"
                (sloth.concat' sloth.xdgConfigHome "/kdeglobals")
                (sloth.concat' sloth.xdgConfigHome "/gtk-2.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-3.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-4.0")
                (sloth.concat' sloth.xdgConfigHome "/dconf")
              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.telegram = pkgs.buildEnv {
        inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "telegram"; };
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "Telegram";
            genericName = "Telegram";
            comment = "Telegram Desktop";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.telegram-desktop}/share/icons/hicolor/256x256/apps/org.telegram.desktop.png";
            type = "Application";
            categories = [
              "Network"
              "InstantMessaging"
            ];
            mimeTypes = [ "x-scheme-handler/tg" ];
            extraConfig = {
              X-Flatpak = appId;
            };
          })
        ];
      };
    };
}
