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

      appId = "com.tencent.QQ";
      fonts = import ./lib/fonts.nix { inherit pkgs; };

      # 全部文字（中英文、数字）统一用 霞鹜文楷 Screen；
      # QQ 自带 @font-face 字体：数字走 resources/app/resource/fonts/AppleColorEmoji.ttf
      # （该字体带 ASCII 数字，一格一个，日期/群人数/QQ 号全变“破数字”）。
      # 用符号链接树重建包，只覆盖 fonts 目录：emoji 换成去掉 ASCII 的版本，
      # DIN 数字字体换成霞鹜文楷，其余文件全部软链回原包。bin/qq 包装脚本
      # 里的绝对路径一并改写到新包。
      qqPatched = pkgs.runCommandLocal "qq-font-patched" { } ''
        src=${pkgs.qq}
        mkdir -p $out
        for f in "$src"/*; do
          base=$(basename "$f")
          [ "$base" = opt ] || [ "$base" = bin ] || ln -s "$f" "$out/$base"
        done
        mkdir -p $out/opt
        for f in "$src"/opt/*; do
          base=$(basename "$f")
          [ "$base" = QQ ] || ln -s "$f" "$out/opt/$base"
        done
        mkdir -p $out/opt/QQ
        for f in "$src"/opt/QQ/*; do
          base=$(basename "$f")
          [ "$base" = resources ] || ln -s "$f" "$out/opt/QQ/$base"
        done
        mkdir -p $out/opt/QQ/resources
        for f in "$src"/opt/QQ/resources/*; do
          base=$(basename "$f")
          [ "$base" = app ] || ln -s "$f" "$out/opt/QQ/resources/$base"
        done
        mkdir -p $out/opt/QQ/resources/app
        for f in "$src"/opt/QQ/resources/app/*; do
          base=$(basename "$f")
          [ "$base" = resource ] || ln -s "$f" "$out/opt/QQ/resources/app/$base"
        done
        mkdir -p $out/opt/QQ/resources/app/resource
        for f in "$src"/opt/QQ/resources/app/resource/*; do
          base=$(basename "$f")
          [ "$base" = fonts ] || ln -s "$f" "$out/opt/QQ/resources/app/resource/$base"
        done

        fonts=$out/opt/QQ/resources/app/resource/fonts
        mkdir -p "$fonts"
        for f in "$src"/opt/QQ/resources/app/resource/fonts/*; do
          ln -s "$f" "$fonts/$(basename "$f")"
        done
        emoji=${fonts.emojiNoAscii}/share/fonts/noto/NotoColorEmoji.ttf
        lxgw=${fonts.primaryFile}
        for f in AppleColorEmoji.ttf AppleColorEmoji-fix.ttf; do
          rm "$fonts/$f"
          cp "$emoji" "$fonts/$f"
        done
        for f in DIN-Medium.ttf DIN-Regular.ttf DINNextLTPro-QQ.ttf DINNextLTPro.ttf; do
          rm "$fonts/$f"
          cp "$lxgw" "$fonts/$f"
        done

        mkdir -p $out/bin
        ${pkgs.gnused}/bin/sed "s|$src|$out|g" "$src/bin/qq" > $out/bin/qq-real
        chmod +x $out/bin/qq-real

        # 沙盒内 PID 都从 2 开始，Electron/AppIndicator 的托盘名
        # org.kde.StatusNotifierItem-<pid>-1 会互相冲突（-2-1 已被飞书占用）。
        # 占两个 PID，让 QQ 的应用进程变成 5 → 托盘名 -5-1。
        cat > $out/bin/qq <<EOF
        #!${pkgs.runtimeShell}
        ${pkgs.coreutils}/bin/sleep 2147483647 &
        s1=\$!
        ${pkgs.coreutils}/bin/sleep 2147483647 &
        s2=\$!
        $out/bin/qq-real "\$@" &
        app=\$!
        wait \$app
        rc=\$?
        kill \$s1 \$s2 2>/dev/null
        exit \$rc
        EOF
        chmod +x $out/bin/qq

        # 主程序不能是软链：Electron 用 /proc/self/exe 推导 resourcesPath 并
        # 以它为 execPath 拉子进程，软链会解析回原包，子渲染进程就又用回原字体。
        rm "$out/opt/QQ/qq"
        cp "$src/opt/QQ/qq" "$out/opt/QQ/qq"
        chmod +x "$out/opt/QQ/qq"
      '';

      qqFonts = fonts.mk { name = "qq-fonts-env"; };

      wrapped = mkNixPak {
        config =
          { sloth, ... }:
          {
            imports = [ ./common.nix ];
            app.package = qqPatched;
            flatpak.appId = appId;

            bubblewrap = {
              env = {
                GTK_THEME = "Adwaita:dark";
                GTK_APPLICATION_PREFER_DARK_THEME = "1";
              };

              bind.dev = [
                "/dev/video0" # 摄像头（视频通话，可选）
              ];

              bind.rw = with sloth; [

                # 配置/数据走 common.nix 的 ~/.var/app/com.tencent.QQ；只额外绑 Downloads

                # Downloads：绑定宿主真实 ~/Downloads（mnixry 的 xdgDownloadDir 写法）
                xdgDownloadDir
              ];

              bind.ro = [

                (sloth.concat' sloth.xdgConfigHome "/kdeglobals")
                (sloth.concat' sloth.xdgConfigHome "/gtk-2.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-3.0")
                (sloth.concat' sloth.xdgConfigHome "/gtk-4.0")
                (sloth.concat' sloth.xdgConfigHome "/dconf")
                [ "${qqFonts}/etc/fonts" "/etc/fonts" ]

              ];
            };
          };
      };

      exePath = pkgs.lib.getExe wrapped.config.script;
    in
    {
      packages.qq = pkgs.buildEnv {
        inherit (wrapped.config.script) name passthru;
        meta = (wrapped.config.script.meta or { }) // { mainProgram = "qq"; };
        paths = [
          wrapped.config.script
          (pkgs.makeDesktopItem {
            name = appId;
            desktopName = "QQ";
            genericName = "QQ";
            comment = "Tencent QQ";
            exec = "${exePath} %U";
            startupNotify = true;
            terminal = false;
            icon = "${pkgs.qq}/share/icons/hicolor/512x512/apps/qq.png";
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
