{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      # nheko 依赖的 olm-3.2.16 被 nixpkgs 标记为 insecure，需要显式放行。
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.permittedInsecurePackages = [ "olm-3.2.16" ];
      };

      mkNixPak = inputs.nixpak.lib.nixpak {
        inherit pkgs;
        inherit (pkgs) lib;
      };

      appId = "io.github.NhekoReborn.Nheko";
      fonts = import ./lib/fonts.nix { inherit pkgs; };

      # 5 个 PID 占位 → 应用 pid 8 → 托盘名 -8-1（与其它沙盒错开）。
      nhekoLauncher = pkgs.runCommandLocal "nheko-launcher" { } ''
        mkdir -p $out/bin
        cat > $out/bin/nheko <<EOF
        #!${pkgs.runtimeShell}
        ${pkgs.coreutils}/bin/sleep 2147483647 & s1=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s2=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s3=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s4=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s5=\$!
        ${pkgs.nheko}/bin/nheko "\$@" & app=\$!
        wait \$app
        rc=\$?
        kill \$s1 \$s2 \$s3 \$s4 \$s5 2>/dev/null
        exit \$rc
        EOF
        chmod +x $out/bin/nheko
      '';

      nhekoFonts = fonts.mk { name = "nheko-fonts-env"; };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = nhekoLauncher;
            app.binPath = "bin/nheko";

            flatpak.appId = appId;
            dbus.policies."org.freedesktop.StatusNotifierItem-8-1" = "own";

            # Nheko 用 libsecret 保存加密密钥；需要访问宿主 Secret Service
            dbus.policies."org.freedesktop.secrets" = "talk";

            bubblewrap = {
              env = {
              };

              bind.rw = with sloth; [
                xdgDownloadDir
              ];

              bind.ro = [
                [ "${nhekoFonts}/etc/fonts" "/etc/fonts" ]
              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.nheko = pkgs.buildEnv {
        inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "nheko"; };
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "nheko";
            genericName = "Matrix Client";
            comment = "Desktop client for the Matrix protocol";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.nheko}/share/icons/hicolor/256x256/apps/nheko.png";
            type = "Application";
            categories = [
              "Network"
              "InstantMessaging"
            ];
            mimeTypes = [ "x-scheme-handler/matrix" ];
            extraConfig = {
              X-Flatpak = appId;
            };
          })
        ];
      };
    };
}
