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

      appId = "com.tencent.WeChatUOS";
      fonts = import ./lib/fonts.nix { inherit pkgs; };
      uosFonts = fonts.mk { name = "wechat-uos-fonts-env"; minimal = true; };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = pkgs.wechat-uos;
            app.binPath = "bin/wechat-uos";

            flatpak.appId = appId;
            dbus.policies."org.freedesktop.StatusNotifierItem-10-1" = "own";

            bubblewrap = {
              env = {
                GTK_THEME = "Adwaita:dark";
                GTK_APPLICATION_PREFER_DARK_THEME = "1";
              };

              bind.rw = with sloth; [
                # Downloads：与其它应用共享宿主 ~/Downloads
                xdgDownloadDir

                # UOS 版仍把数据写在 ~/.xwechat，这里持久化到 var
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/.var/app/${appId}/xwechat"))
                  (sloth.concat' sloth.homeDir "/.xwechat")
                ]
                # 账号/消息存储：UOS 默认 ~/xwechat_files（之前没绑，登录态和文件每次都丢）
                [
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/.var/app/${appId}/xwechat_files"))
                  (sloth.concat' sloth.homeDir "/xwechat_files")
                ]
              ];

              bind.ro = [
                [ "${uosFonts}/etc/fonts" "/etc/fonts" ]
                # UOS 启动脚本会直接调 /usr/bin/lsblk
                [ "${pkgs.util-linux}/bin/lsblk" "/usr/bin/lsblk" ]
                # 设备指纹（登录态校验）可能读取这些
                "/sys/dev"
                "/sys/devices"
                "/var/lib/dbus/machine-id"
              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;

      # 过滤 UOS 启动脚本的 /usr/bin/lsblk 噪音（FHS 内层看不到外层绑定）
      filtered = pkgs.writeShellScriptBin "wechat-uos" ''
        ${exePath} "$@" 2> >(${pkgs.gnugrep}/bin/grep -v --line-buffered '/usr/bin/lsblk: ' >&2)
      '';
    in
    {
      packages.wechat-uos = pkgs.buildEnv {
        name = "wechat-uos";
        meta.mainProgram = "wechat-uos";
        paths = [
          filtered
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "WeChat (UOS)";
            genericName = "WeChat";
            comment = "Tencent WeChat UOS build";
            exec = "${filtered}/bin/wechat-uos %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.wechat-uos}/share/icons/hicolor/256x256/apps/com.tencent.wechat.png";
            type = "Application";
            categories = [
              "Network"
              "InstantMessaging"
            ];
            mimeTypes = [ "x-scheme-handler/weixin" ];
            extraConfig = {
              X-Flatpak = appId;
            };
          })
        ];
      };
    };
}
