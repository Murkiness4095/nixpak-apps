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

      appId = "dev.vencord.Vesktop";
      fonts = import ./lib/fonts.nix { inherit pkgs; };
      vFonts = fonts.mk { name = "vesktop-fonts-env"; };

      # 6 个 PID 占位 → 应用 pid 9 → 托盘名 -9-1
      vesktopLauncher = pkgs.runCommandLocal "vesktop-launcher" { } ''
        mkdir -p $out/bin
        cat > $out/bin/vesktop <<EOF
        #!${pkgs.runtimeShell}
        ${pkgs.coreutils}/bin/sleep 2147483647 & s1=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s2=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s3=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s4=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s5=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s6=\$!
        ${pkgs.vesktop}/bin/vesktop "\$@" & app=\$!
        wait \$app
        rc=\$?
        kill \$s1 \$s2 \$s3 \$s4 \$s5 \$s6 2>/dev/null
        exit \$rc
        EOF
        chmod +x $out/bin/vesktop
      '';

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = vesktopLauncher;
            app.binPath = "bin/vesktop";

            flatpak.appId = appId;

            env = {
              # 文件选择器走 GTK，强制深色（不影响 Vesktop 自己的主题设置）
              GTK_THEME = "Adwaita:dark";
              GTK_APPLICATION_PREFER_DARK_THEME = "1";
            };

            bubblewrap = {
              bind.dev = [ "/dev/video0" ]; # 视频通话

              bind.rw = with sloth; [
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/.var/app/${appId}/config/vesktop"))
                  (sloth.concat' sloth.homeDir "/.config/vesktop")
                ]
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/.var/app/${appId}/config/discord"))
                  (sloth.concat' sloth.homeDir "/.config/discord")
                ]
                xdgDownloadDir
              ];

              bind.ro = [
                [ "${vFonts}/etc/fonts" "/etc/fonts" ]
                # GTK 对话框的深色主题/图标来自宿主（Electron 自带 GTK 没有 Adwaita-dark）
                "/run/current-system/sw/share/themes"
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
      packages.vesktop = pkgs.buildEnv {
        inherit (wrapped.config.script) name meta passthru;
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "Vesktop";
            genericName = "Discord";
            comment = "Vesktop (Discord client)";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.vesktop}/share/icons/hicolor/256x256/apps/vesktop.png";
            type = "Application";
            categories = [
              "Network"
              "InstantMessaging"
            ];
            mimeTypes = [ "x-scheme-handler/discord" ];
            extraConfig = {
              X-Flatpak = appId;
            };
          })
        ];
      };
    };
}
