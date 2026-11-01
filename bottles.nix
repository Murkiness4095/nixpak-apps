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

      appId = "com.usebottles.bottles";
      fonts = import ./lib/fonts.nix { inherit pkgs; };
      bottlesFonts = fonts.mk { name = "bottles-fonts-env"; };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = pkgs.bottles-unwrapped;
            app.binPath = "bin/bottles";

            dbus.policies."com.usebottles.bottles" = "own";
            dbus.policies."com.usebottles.*" = "own";


            # Bottles 用 GTK 文件对话框选前缀/安装器
            bubblewrap = {
              bind.dev = [
                "/dev/nvidia0"
                "/dev/nvidiactl"
                "/dev/nvidia-modeset"
                "/dev/nvidia-uvm"
                "/dev/nvidia-uvm-tools"
              ];
              # Bottles 运行 UMU 游戏需要能访问 umu-launcher 的 store 路径
              extraStorePaths = [ pkgs.umu-launcher ];
              bind.rw = with sloth; [
                xdgDownloadDir
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/Bottles"))
                  (sloth.concat' sloth.homeDir "/Bottles")
                ]
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/Games"))
                  (sloth.concat' sloth.homeDir "/Games")
                ]
                "/mnt"
                "/media"
                "/run/media"
              ];

              env = {
                GTK_IM_MODULE = "";
                QT_IM_MODULE = "";
                XMODIFIERS = "";
              };

              bind.ro = [
                [ "${bottlesFonts}/etc/fonts" "/etc/fonts" ]
                "/etc/zoneinfo"
                "/run/opengl-driver-32"
              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.bottles = pkgs.buildEnv {
        inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "bottles"; };
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "Bottles";
            genericName = "Wineprefix Manager";
            comment = "Bottles (sandboxed)";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.bottles-unwrapped}/share/icons/hicolor/scalable/apps/com.usebottles.bottles.svg";
            type = "Application";
            categories = [ "Game" "Utility" ];
            extraConfig = { X-Flatpak = appId; };
          })
        ];
      };
    };
}
