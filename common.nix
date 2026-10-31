# 所有 nixpak 沙盒的公共基础配置。
#
# 约定：common 只放“所有应用都成立”的隔离策略。
# 应用/厂商专属内容（NVIDIA 设备、托盘 SNI、Wine/umu 路径等）放各自应用模块，
# 避免 common 变成例外集合。
#
# 设计目标（隔离优先）：
#  - 宿主 $HOME / ~/.config / ~/.local/share 默认不可见；应用只能看到显式绑定。
#  - 不整绑宿主 $XDG_RUNTIME_DIR，只绑定具体 socket（wayland/at-spi/gvfsd/dconf），
#    避免同一用户下跨沙盒访问其它实例的 nixpak-bus-*（与 mnixry 的做法一致）。
#  - /tmp 使用私有 tmpfs；不绑定宿主 /tmp（当前全部应用 Wayland-only）。
#  - portal 只放行接口白名单；FileChooser 默认关闭，需要时按应用显式开启。
#  - XDG 目录重定向到 ~/.var/app/<appId>/{config,data,cache}，
#    应用特定的历史目录可由各模块再挂到对应子路径（保持数据不迁移）。
{ config ? { }, lib, pkgs ? { }, sloth ? { }, ... }@args:
let
  inherit (lib) mkDefault;
  cfg = config.nixpakCommon;

  portalCallBase = [
    "org.freedesktop.DBus.Introspectable.*"
    "org.freedesktop.portal.OpenURI.*"
    "org.freedesktop.portal.Settings.*"
    "org.freedesktop.portal.Notification.*"
    "org.freedesktop.portal.Screenshot.*"
    "org.freedesktop.portal.ScreenCast.*"
    "org.freedesktop.portal.Request.*"
  ];
in
if args ? self then { } else {
  options.nixpakCommon.fileChooser.enable =
    lib.mkEnableOption "allow FileChooser portal";

  config = {
    fonts.enable = mkDefault false;

    etc.sslCertificates.enable = mkDefault true;

    gpu.enable = mkDefault true;
    gpu.provider = mkDefault "nixos";

    dbus.enable = mkDefault true;
    dbus.policies = lib.mapAttrs (name: value: mkDefault value) {
      "org.freedesktop.Notifications" = "talk";
      "ca.desrt.dconf" = "talk";
      "org.kde.StatusNotifierWatcher" = "talk";
      "org.freedesktop.StatusNotifierHost" = "own";
      "org.kde.*" = "own";
      "org.freedesktop.portal.Fcitx" = "talk";
      "org.freedesktop.portal.Fcitx.*" = "talk";
      "org.freedesktop.portal.IBus" = "talk";
      "org.freedesktop.portal.IBus.*" = "talk";
    };

    dbus.rules.call."org.freedesktop.portal.Desktop" =
      portalCallBase
      ++ lib.optional cfg.fileChooser.enable "org.freedesktop.portal.FileChooser.*"
      ++ lib.optional cfg.fileChooser.enable "org.freedesktop.DBus.Properties.Get";

    dbus.rules.broadcast."org.freedesktop.portal.Desktop" = [
      "org.freedesktop.portal.Request.*"
      "org.freedesktop.portal.Settings.*"
      "org.freedesktop.portal.Notification.*"
      "org.freedesktop.portal.OpenURI.*"
      "org.freedesktop.portal.Screenshot.*"
      "org.freedesktop.portal.ScreenCast.*"
    ];

    bubblewrap = {
      network = mkDefault true;

      env = {
        GTK_IM_MODULE = mkDefault "fcitx";
        QT_IM_MODULE = mkDefault "fcitx";
        XMODIFIERS = mkDefault "@im=fcitx";
        LD_LIBRARY_PATH = mkDefault (sloth.concat [ "/run/opengl-driver/lib:/run/opengl-driver-32/lib:" (sloth.envOr "LD_LIBRARY_PATH" "") ]);
        QT_QPA_PLATFORM = mkDefault "wayland";
        ELECTRON_OZONE_PLATFORM_HINT = mkDefault "wayland";
        NIXOS_OZONE_WL = mkDefault "1";
        PATH = mkDefault (
          sloth.concat [
            "${pkgs.xdg-utils}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:${pkgs.findutils}/bin:${pkgs.procps}/bin:${pkgs.glibc.bin}/bin:"
            (sloth.envOr "PATH" "")
          ]
        );
      };

      extraStorePaths = [ pkgs.xdg-utils ];

      bind.dev = [
        "/dev/dri"
        "/dev/snd"
        "/dev/shm"
      ];

      # 只绑具体 runtime socket；不要整绑宿主 $XDG_RUNTIME_DIR。
      # 未绑定的 socket 路径会由 bwrap 在沙盒根里创建挂载点。
      bind.rw = lib.mkBefore (
        with sloth;
        [
          (sloth.concat [
            sloth.runtimeDir
            "/"
            (sloth.envOr "WAYLAND_DISPLAY" "no")
          ])
          (sloth.concat' sloth.runtimeDir "/at-spi/bus")
          (sloth.concat' sloth.runtimeDir "/gvfsd")
          (sloth.concat' sloth.runtimeDir "/dconf")

          (sloth.concat' sloth.xdgCacheHome "/fontconfig")
          (sloth.concat' sloth.xdgCacheHome "/mesa_shader_cache")
          (sloth.concat' sloth.xdgCacheHome "/mesa_shader_cache_db")
          (sloth.concat' sloth.xdgCacheHome "/radv_builtin_shaders")

          # XDG 目录重定向到每应用私有目录
          [
            (sloth.mkdir sloth.appConfigDir)
            sloth.xdgConfigHome
          ]
          [
            (sloth.mkdir sloth.appDataDir)
            sloth.xdgDataHome
          ]
          [
            (sloth.mkdir sloth.appCacheDir)
            sloth.xdgCacheHome
          ]
        ]
      );

      tmpfs = [ "/tmp" ];

      bind.ro = with sloth; [
        [ "${pkgs.bashInteractive}/bin/bash" "/bin/sh" ]
        [ "${pkgs.bashInteractive}/bin/bash" "/bin/bash" ]
        "/etc/os-release"
        "/etc/lsb-release"
        (sloth.concat' sloth.runtimeDir "/doc")
        "/etc/localtime"
        "/etc/egl"
        "/etc/static/egl"
        "/etc/static/alsa"
        "/etc/alsa"

        # GTK 对话框通过 fontconfig 读字体；nixpak 只挂应用闭包，字体的 store 路径需显式挂
        "${pkgs.lxgw-wenkai-screen}"
        "${pkgs.noto-fonts}"
        "${pkgs.noto-fonts-cjk-sans}"
        # GTK 文件对话框需要 org.gtk.Settings.FileChooser schema，否则 g_settings 直接 abort；
        # 宿主没有 /run/current-system/sw/share/glib-2.0/schemas，从 gtk3 包绑定
        [ "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas" "/run/current-system/sw/share/glib-2.0/schemas" ]
        "/run/current-system/sw/share/mime"
        "/run/current-system/sw/share/icons"
        "/run/current-system/sw/share/applications"

        "/etc/passwd"
        "/etc/group"
        "/etc/machine-id"
      ];


      sockets = {
        wayland = mkDefault true;
        pipewire = mkDefault true;
        # 部分应用依赖 PulseAudio 兼容层；只给 pipewire socket 时可能无声
        pulse = mkDefault true;
        # 严格 Wayland：不挂任何 X11 socket（nixpak 默认也是 false，这里显式写出）
        x11 = mkDefault false;
      };
    };
  };
}
