{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # 6 个 PID 占位 → 应用 pid 7 → 托盘名 -7-1
      bottlesLauncher = pkgs.runCommandLocal "bottles-launcher" { } ''
        mkdir -p $out/bin
        cat > $out/bin/bottles <<EOF
        #!${pkgs.runtimeShell}
        ${pkgs.coreutils}/bin/sleep 2147483647 & s1=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s2=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s3=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s4=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s5=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 & s6=\$!
        ${pkgs.bottles-unwrapped}/bin/bottles "\$@" & app=\$!
        wait \$app
        rc=\$?
        kill \$s1 \$s2 \$s3 \$s4 \$s5 \$s6 2>/dev/null
        exit \$rc
        EOF
        chmod +x $out/bin/bottles
      '';

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
            app.package = bottlesLauncher;
            app.binPath = "bin/bottles";

            # Bottles 自身托盘：pid 7 → -7-1（仅本模块放行，不改 common）
            dbus.policies."org.freedesktop.StatusNotifierItem-7-1" = "own";
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
