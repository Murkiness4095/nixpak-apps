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

      appId = "com.heroicgameslauncher.hgl";
      fonts = import ./lib/fonts.nix { inherit pkgs; };
      heroicFonts = fonts.mk { name = "heroic-fonts-env"; };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = pkgs.heroic-unwrapped;
            app.binPath = "bin/heroic";

            flatpak.appId = appId;
            dbus.policies."org.freedesktop.StatusNotifierItem-2-1" = "own";

            env = {
              GTK_THEME = "Adwaita:dark";
              GTK_APPLICATION_PREFER_DARK_THEME = "1";
            };

            bubblewrap = {
              bind.dev = [
                "/dev/nvidia0"
                "/dev/nvidiactl"
                "/dev/nvidia-modeset"
                "/dev/nvidia-uvm"
                "/dev/nvidia-uvm-tools"
              ];
              bind.rw = with sloth; [
                xdgDownloadDir
                # 游戏安装目录：仅暴露 ~/Games，避免整绑宿主 $HOME
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/Games"))
                  (sloth.concat' sloth.homeDir "/Games")
                ]
                "/mnt"
                "/media"
                "/run/media"
                # 现有前缀/自定义 Proton 在 home 下，需显式绑定
                (sloth.concat' sloth.homeDir "/123game")
                (sloth.concat' sloth.homeDir "/.local/share/Steam/compatibilitytools.d")
                (sloth.concat' sloth.homeDir "/.steam/steam")
              ];

              bind.ro = [
                [ "${heroicFonts}/etc/fonts" "/etc/fonts" ]
                "/etc/zoneinfo"
                "/run/opengl-driver-32"
                # GTK 对话框深色主题
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
      packages.heroic = pkgs.buildEnv {
        inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "heroic"; };
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "Heroic";
            genericName = "Games Launcher";
            comment = "Heroic Games Launcher (sandboxed)";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.heroic-unwrapped}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg";
            type = "Application";
            categories = [
              "Game"
            ];
            mimeTypes = [ "x-scheme-handler/heroic" ];
            extraConfig = {
              X-Flatpak = appId;
            };
          })
        ];
      };
    };
}
