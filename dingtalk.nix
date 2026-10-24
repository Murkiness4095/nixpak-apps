{ inputs, lib, ... }:
let
  mkPatched =
    { pkgs, unwrapped }:
    let
      appVersion = lib.removeSuffix "\n" (
        builtins.readFile "${unwrapped}/opt/apps/com.alibabainc.dingtalk/files/version"
      );
      appDir = "${unwrapped}/opt/apps/com.alibabainc.dingtalk/files/${appVersion}";
    in
    pkgs.runCommandLocal "dingtalk-font-patched" {
      nativeBuildInputs = [
        pkgs.makeWrapper
        pkgs.python3Packages.fonttools
      ];
    } ''
      src=${unwrapped}
      rsrc=$out/opt/apps/com.alibabainc.dingtalk
      clone_except() {
        s=$1; d=$2; skip=$3
        mkdir -p "$d"
        for f in "$s"/*; do
          b=$(basename "$f")
          [ "$b" = "$skip" ] || ln -s "$f" "$d/$b"
        done
      }
      mkdir -p $out
      for f in "$src"/*; do
        b=$(basename "$f")
        case "$b" in opt|bin) ;; *) ln -s "$f" "$out/$b" ;; esac
      done
      clone_except "$src/opt" "$out/opt" apps
      clone_except "$src/opt/apps" "$out/opt/apps" com.alibabainc.dingtalk
      clone_except "$src/opt/apps/com.alibabainc.dingtalk" "$rsrc" files
      clone_except "$src/opt/apps/com.alibabainc.dingtalk/files" "$rsrc/files" ${appVersion}
      clone_except "$src/opt/apps/com.alibabainc.dingtalk/files/${appVersion}" "$rsrc/files/${appVersion}" Resources
      clone_except "$src/opt/apps/com.alibabainc.dingtalk/files/${appVersion}/Resources" "$rsrc/files/${appVersion}/Resources" fonts
      clone_except "$src/opt/apps/com.alibabainc.dingtalk/files/${appVersion}/Resources/fonts" "$rsrc/files/${appVersion}/Resources/fonts" ""

      # 官方 UI 正文字体 = Alibaba PuHuiTi 3.0（regular.otf），直接换成霞鹜文楷。
      # Qt 原生窗口按族名 "Alibaba PuHuiTi 3.0" 查找，映射交给沙盒 fontconfig
      # 的 alias（见 dtFonts）；改字体 name 表会导致 Qt 崩溃，不用。
      fonts=$rsrc/files/${appVersion}/Resources/fonts
      rm "$fonts/regular.otf"
      cp ${(import ./lib/fonts.nix { inherit pkgs; }).primaryFile} "$fonts/regular.otf"

      # 主程序必须是实体文件，否则 /proc/self/exe 会指回原包，Resources 也回原包
      appdir=$rsrc/files/${appVersion}
      rm "$appdir/com.alibabainc.dingtalk" "$appdir/dingtalk_shell"
      cp "${appDir}/com.alibabainc.dingtalk" "$appdir/com.alibabainc.dingtalk"
      cp "${appDir}/dingtalk_shell" "$appdir/dingtalk_shell"
      chmod +x "$appdir/com.alibabainc.dingtalk" "$appdir/dingtalk_shell"

      mkdir -p $out/bin
      makeWrapper "$appdir/com.alibabainc.dingtalk" "$out/bin/dingtalk" \
        --chdir "$appdir" \
        --set QT_QPA_PLATFORM wayland \
        --set-default QT_IM_MODULE fcitx \
        --set QT_PLUGIN_PATH "$appdir" \
        --add-flags "--force-dark-mode --enable-features=WebContentsForceDark" \
        --prefix LD_PRELOAD ' ' "$appdir/plugins/dtwebview/libcef.so"
      # 注意：不能改 cwd。钉钉内部依赖 cwd=应用目录（改到 HOME/Downloads 都会
      # 在 InitDeviceSetting 之后崩溃），所以文件选择器默认目录只能保持应用目录。

      # 每个沙盒内的进程 PID 都从 2 开始，Qt/AppIndicator 会用
      # org.kde.StatusNotifierItem-<pid>-1 注册托盘，多个沙盒同时在跑就会
      # 互相抢同一个名字（日志：failed to register service ...-2-1）。
      # 这里先挂一个常驻子进程把应用的 PID 顶到 4，托盘名变成 -4-1，避免冲突。
      mv $out/bin/dingtalk $out/bin/dingtalk-real
      cat > $out/bin/dingtalk <<EOF
      #!${pkgs.runtimeShell}
      ${pkgs.coreutils}/bin/sleep 2147483647 &
      spacer=\$!
      $out/bin/dingtalk-real "\$@" &
      app=\$!
      wait \$app
      rc=\$?
      kill \$spacer 2>/dev/null
      exit \$rc
      EOF
      chmod +x $out/bin/dingtalk
    '';

  mkSandbox =
    { pkgs, unwrapped }:
    let
      mkNixPak = inputs.nixpak.lib.nixpak {
        inherit pkgs;
        inherit (pkgs) lib;
      };
      appId = "com.alibabainc.dingtalk";
      fonts = import ./lib/fonts.nix { inherit pkgs; };

      dtFonts = fonts.mk {
        name = "dingtalk-fonts-env";
        # 钉钉 Qt 原生窗口（文件选择器等）按这些族名要字体
        aliases = [
          "Alibaba PuHuiTi 3.0"
          "Alibaba PuHuiTi"
          "AlibabaPuHuiTi3.0"
        ];
      };

      # 覆盖宿主 GTK 字体设置：钉钉自带 Pango 读不了 LXGW，用 Noto CJK
      gtkSettings = pkgs.writeTextDir "settings.ini" ''
        [Settings]
        gtk-font-name=Noto Sans CJK SC 11
        gtk-theme-name=Adwaita-dark
        gtk-application-prefer-dark-theme=1
      '';

      # GTK 对话框用 Noto CJK 渲染（钉钉自带的旧 Pango/FreeType 读不了 LXGW）
      gtkFonts = pkgs.runCommandLocal "dingtalk-gtk-fonts" { } ''
        mkdir -p $out/etc/fonts
        cat > $out/etc/fonts/fonts.conf <<EOF
<fontconfig>
  <dir>${pkgs.noto-fonts-cjk-sans}</dir>
  <dir>${pkgs.noto-fonts}</dir>
  <cachedir>${pkgs.makeFontsCache {
    inherit (pkgs) fontconfig;
    fontDirectories = [ pkgs.noto-fonts-cjk-sans pkgs.noto-fonts ];
  }}</cachedir>
</fontconfig>
EOF
      '';

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            nixpakCommon.fileChooser.enable = true;
            app.package = unwrapped;
            app.binPath = "bin/dingtalk";
            flatpak.appId = appId;

            bubblewrap = {
              env = {
                GTK_USE_PORTAL = "1";
                GTK_THEME = "Adwaita:dark";
                GTK_APPLICATION_PREFER_DARK_THEME = "1";
              };

              bind.dev = [
                "/dev/video0"
              ];

              bind.rw = with sloth; [
                xdgDownloadDir
              ];

              bind.ro = [

                # DingTalk 内部大量 popen("/bin/sh")；nixpak 根是空的，必须补上

                (sloth.concat' sloth.xdgConfigHome "/kdeglobals")
                (sloth.concat' sloth.xdgConfigHome "/gtk-2.0")
                [ "${gtkSettings}/settings.ini" (sloth.concat' sloth.xdgConfigHome "/gtk-3.0/settings.ini") ]
                (sloth.concat' sloth.xdgConfigHome "/gtk-4.0")
                (sloth.concat' sloth.xdgConfigHome "/dconf")
                [ "${gtkFonts}/etc/fonts" "/etc/fonts" ]
                "/run/current-system/sw/share/themes"

              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;

      # 钉钉启动后会 kill 掉自己的父进程（脱离终端），直接前台跑会让 nix run 以
      # 137 退出。setsid 后台启动保留，但不再重定向，日志照常输出到终端。
      launcher = pkgs.writeShellScriptBin "dingtalk" ''
        ${pkgs.util-linux}/bin/setsid ${exePath} "$@" </dev/null &
      '';
    in
    pkgs.buildEnv {
      inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "dingtalk"; };
      paths = [
        launcher
        (pkgs.makeDesktopItem {
          name = appId;
          desktopName = "DingTalk";
          genericName = "DingTalk";
          comment = "DingTalk";
          exec = "${launcher}/bin/dingtalk %U";
          startupNotify = true;
          terminal = false;
          icon = "${unwrapped}/share/icons/hicolor/256x256/apps/com.alibabainc.dingtalk.png";
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
in
{
  perSystem =
    { system, config, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      # 打包由 unwrapped/dingtalk.nix 提供（dingtalk-unwrapped），
      # 这里只负责字体替换 + nixpak 沙盒 + 桌面入口。
      packages.dingtalk = mkSandbox {
        inherit pkgs;
        unwrapped = mkPatched {
          inherit pkgs;
          unwrapped = config.packages.dingtalk-unwrapped;
        };
      };
    };
}
