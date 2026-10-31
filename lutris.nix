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

      appId = "net.lutris.Lutris";
      fonts = import ./lib/fonts.nix { inherit pkgs; };
      lutrisFonts = fonts.mk { name = "lutris-fonts-env"; };
      gpuTools = pkgs.symlinkJoin {
        name = "lutris-gpu-tools";
        paths = [
          pkgs.vulkan-tools
          pkgs.mesa-demos
          pkgs.pciutils
        ];
      };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = pkgs.lutris;
            app.binPath = "bin/lutris";

            flatpak.appId = appId;

            dbus.policies."org.freedesktop.StatusNotifierItem-2-1" = "own";
            dbus.policies."net.lutris.Lutris" = "own";

            nixpakCommon.fileChooser.enable = true;

            bubblewrap = {
              bind.dev = [
                "/dev/nvidia0"
                "/dev/nvidiactl"
                "/dev/nvidia-modeset"
                "/dev/nvidia-uvm"
                "/dev/nvidia-uvm-tools"
              ];
              # GPU/驱动探测
              extraStorePaths = [
                pkgs.pciutils
                pkgs.mesa-demos
                pkgs.vulkan-tools
              ];

              bind.rw = with sloth; [
                xdgDownloadDir
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/Games"))
                  (sloth.concat' sloth.homeDir "/Games")
                ]
                "/mnt"
                "/media"
                "/run/media"
                [ "${gpuTools}" "/usr" ]
              ];

              bind.ro = [
                [ "${lutrisFonts}/etc/fonts" "/etc/fonts" ]
                "/etc/zoneinfo"
                "/run/opengl-driver-32"
                "/sys"
              ];

              env = {
                GTK_IM_MODULE = "";
                QT_IM_MODULE = "";
                XMODIFIERS = "";
              };
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.lutris = pkgs.buildEnv {
        inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "lutris"; };
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "Lutris";
            genericName = "Game Manager";
            comment = "Lutris (sandboxed)";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.lutris}/share/icons/hicolor/256x256/apps/lutris.png";
            type = "Application";
            categories = [ "Game" ];
            extraConfig = { X-Flatpak = appId; };
          })
        ];
      };
    };
}
