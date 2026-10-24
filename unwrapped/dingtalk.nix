# DingTalk（钉钉）— 直接封装官方预编译二进制（flake-parts 单文件模块）
#
# 打包策略：不重新构建，消费官方分发产物：
#   * Linux  → .deb（/opt/apps/com.alibabainc.dingtalk 应用树，CEF + Qt5 运行时）：
#              autoPatchelfHook 解析 NEEDED；复刻官方 postinst 面向现代系统的库裁剪；
#              用 Nix 启动器固定 Qt/CEF 环境，不运行厂商的旧 glibc 探测脚本。
#   * Darwin → .dmg → DingTalkInstaller.pkg（xar）→ Payload（pbzx + cpio）→ DingTalk.app
#              （保留厂商代码签名，dontFixup 跳过全部 fixup）。
# 因此跟随官方更新只需改下面 `sources` 块的 version/hash（macOS 另有 build），URL 从这些字段派生。
#
# 用法：
#   nix run <本 flake/目录/仓库>#dingtalk
#   同仓库其他模块直接： self.packages."${pkgs.stdenv.hostPlatform.system}".dingtalk
#   只有 sources 里声明了的系统才产出该包（本仓库不声明 x86_64-darwin）。
#
# 升级到官方新版：三个平台的“最新产物 URL”可由官网下载页的跳转地址反查，
# 再用 prefetch 拿新 hash，替换 sources 里对应项即可：
#   curl -sL -r 0-0 -o /dev/null -w '%{url_effective}\n' 'https://www.dingtalk.com/win/d/qd=linux_amd64'
#   curl -sL -r 0-0 -o /dev/null -w '%{url_effective}\n' 'https://www.dingtalk.com/win/d/qd=linux_arm64'
#   curl -sL -r 0-0 -o /dev/null -w '%{url_effective}\n' 'https://www.dingtalk.com/mac/d/qd=mac-arm64'
#   nix store prefetch-file --json <新 URL>   # 输出里的 hash 换进 sources
{ inputs, lib, ... }:
let
  # ── 官方发行版声明：跟随官方更新的唯一改动点 ──────────────────────────────
  sources = {
    x86_64-linux = rec {
      version = "8.3.1.261008001";
      url = "https://dtapp-pub.dingtalk.com/dingtalk-desktop/xc_dingtalk_update/linux_deb/Release/com.alibabainc.dingtalk_${version}_amd64.deb";
      hash = "sha256-NatoDe0QSrzcU6Z/z8/ytWR5mX8W6Kv+EcQfv1j1gl4=";
    };
    aarch64-linux = rec {
      version = "8.3.1.261008001";
      url = "https://dtapp-pub.dingtalk.com/dingtalk-desktop/xc_dingtalk_update/linux_deb/Release/com.alibabainc.dingtalk_${version}_arm64.deb";
      hash = "sha256-GcMePt3sN8W1yK3FsSp9uyC5zQQWuXhyR3pvhlrPhgM=";
    };
    aarch64-darwin = rec {
      version = "9.0.2";
      build = "59049656";
      url = "https://dtapp-pub.dingtalk.com/dingtalk-desktop/mac_dmg/Release/DingTalk_v${version}-Installer_${build}_arm64.dmg";
      hash = "sha256-GNwuPkCi1qF80YpJzYzgutcONBPFH650aQHYA2cqU3Y=";
    };
  };

  meta = {
    description = "Official DingTalk desktop client packaged from vendor binaries";
    longDescription = ''
      钉钉（DingTalk）桌面客户端。本包不重新构建源码，直接封装官方分发的
      Linux .deb 与 macOS .dmg 二进制产物。
    '';
    homepage = "https://www.dingtalk.com/download";
    license = lib.licenses.unfree;
    mainProgram = "dingtalk";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };

  # ---------------------------------------------------------------- Linux (deb)
  mkLinux =
    {
      pkgs,
      src,
      version,
    }:
    let
      # 官方预编译 libaprutil/libapr 绑定 libcrypt.so.1 并要求 GLIBC_2.2.5 版本；
      # nixpkgs 默认 libxcrypt（--enable-hashes=strong）只产 libcrypt.so.2、仅导出
      # XCRYPT_* 版本。把哈希集合换成 all（含遗留 DES/MD5）即切换为 libcrypt.so.1
      # SONAME 并导出 glibc 版本别名（ldd 绑定实测通过）。
      libcryptCompat = pkgs.libxcrypt.overrideAttrs (old: {
        configureFlags = map (lib.replaceStrings [ "hashes=strong" ] [ "hashes=all" ]) (
          old.configureFlags or [ ]
        );
      });
    in
    pkgs.stdenv.mkDerivation {
      pname = "dingtalk";
      inherit version src meta;

      nativeBuildInputs = with pkgs; [
        dpkg
        autoPatchelfHook
      ];

      # 官方 deb 的 control 没有 Depends：全部运行期库在此列全。
      # autoPatchelfHook 解析出的库排在 $ORIGIN 之前（见 appendRunpaths），
      # 系统库优先，随包旧库只兜底 nix 里没有的裸 soname。
      buildInputs = with pkgs; [
        gtk3
        glib
        pango
        cairo
        atk
        gdk-pixbuf
        gnutls
        libglvnd
        mesa
        libdrm
        libsm
        libice
        libx11
        libxext
        libxcomposite
        libxdamage
        libxfixes
        libxrandr
        libxrender
        libxtst
        libxcb
        libxkbcommon
        xcbutil
        xcbutilimage
        xcbutilkeysyms
        xcbutilrenderutil
        xcbutilwm
        nss
        nspr
        cups
        dbus
        expat
        alsa-lib
        libpulseaudio
        fontconfig
        freetype
        harfbuzz
        zlib
        xz
        # 首轮构建 autoPatchelf 实测报缺的 soname，逐项补齐。
        stdenv.cc.cc.lib # libstdc++.so.6（编译器运行库必须显式入 rpath）
        curl # libcurl.so.4：随包旧 libcurl 已裁剪，由 nix 提供（连带消解其 librtmp/libldap_r-2.4 裸 soname）
        libcryptCompat # libcrypt.so.1：libapr* 需要的 glibc 版本别名（见上定义）
        e2fsprogs # libcom_err.so.2
        libGLU
        libxmu
        libXt
        gtk2 # doctor 与随包 gtkglext 栈（libpangox-1.0 无 nix 包，仍保持忽略）
      ];

      # 随包库之间互相引用的裸 soname（libcef.so、libQt5*、libavcodec 等）不在
      # nix 的库里，跳过这些告警；运行期由 $ORIGIN（应用目录）兜底解析。
      autoPatchelfIgnoreMissingDeps = true;

      # deb 的 data.tar 交给 dpkg-deb 解开，顺带保留文件权限。
      # 库裁剪放在解包树上先行执行：autoPatchelf 会连构建目录一起搜同名
      # soname（实测 libcurl 命中 /build 下的未裁剪副本），届时 rpath 会指向
      # 构建期路径或被随包旧库抢先，系统库反而落选。
      unpackPhase = ''
        runHook preUnpack
        dpkg-deb --extract "$src" .

        # 复刻官方 postinst 面向“现代 glibc + 现代发行版”的库裁剪：
        #   libm/libstdc++/libgbm/libGLX/libGLdispatch  → glibc、mesa、libglvnd
        #   libharfbuzz（官方在 ubuntu>=22 删除）        → 系统 harfbuzz
        #   libffi.so.6.0.4（非麒麟分支删除）            → 系统 libffi
        #   随包 libcurl（依赖 nixpkgs 没有的 libldap_r-2.4 等裸 soname）
        #                                              → 系统 curl
        vendoredDir="opt/apps/com.alibabainc.dingtalk/files/$(cat opt/apps/com.alibabainc.dingtalk/files/version)"
        rm -f "$vendoredDir"/libm.so.6 \
              "$vendoredDir"/envlib.so \
              "$vendoredDir"/libgbm.so* \
              "$vendoredDir"/libGLX.so* \
              "$vendoredDir"/libGLdispatch.so* \
              "$vendoredDir"/libffi.so.6.0.4 \
              "$vendoredDir"/libstdc++.so.6* \
              "$vendoredDir"/libharfbuzz.so* \
              "$vendoredDir"/libcurl.so*

        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall

        appRoot=$out/opt/apps/com.alibabainc.dingtalk
        mkdir -p "$appRoot"
        cp -a opt/apps/com.alibabainc.dingtalk/. "$appRoot/"

        # 厂商脚本按 ldd 输出的第五列猜 glibc 版本；Nix 的格式不同，会误走
        # 旧 glibc 分支并预加载 envlib.so。该库覆盖 getrandom/fcntl64 等符号，
        # 实测令 NSS_NoDB_Init 返回 SEC_ERROR_IO (-8023)。Nix 已固定现代 glibc，
        # 不需要这层兼容逻辑；移除旧入口，仅保留 Qt 环境与 CEF 预加载。
        rm "$appRoot/files/Elevator.sh"

        # 菜单启动器不一定支持 ICO；安装官方 PNG 到标准 hicolor 目录。
        appDir="$appRoot/files/$(cat "$appRoot/files/version")"
        iconPath="$out/share/icons/hicolor/256x256/apps/com.alibabainc.dingtalk.png"
        install -Dm644 "$appDir/Resources/image/common/about/logo.png" "$iconPath"

        runHook postInstall
      '';

      # 随包 ELF 含快照/自校验内容，strip 有损坏风险（与上游 deb 状态保持一致）。
      dontStrip = true;

      # 随包库就在应用目录内：$ORIGIN 兜底；autoPatchelf 解析出的 nix 库排在
      # 其前，同名 soname 一律系统库优先。
      appendRunpaths = [
        # dlopen 发生在 libcef.so 内；runtimeDependencies 仅作用于可执行文件。
        "${lib.getLib pkgs.udev}/lib"
        "$ORIGIN"
        "$ORIGIN/plugins/dtwebview"
      ];
    };

  # -------------------------------------------------------------- Darwin (dmg)
  mkDarwin =
    {
      pkgs,
      src,
      version,
    }:
    let
      # Apple 的 pbzx 流解码器（dmg 里的 pkg → Payload 为 pbzx + cpio 组合）。
      # 不用 nixpkgs 的 pbzx 工具：它内置的老 libxar 打不开新版 installer pkg，
      # 已在真实产物上验证过本脚本（408MB Payload → 968MB cpio，6624 个文件）。
      pbzxDecode = pkgs.writeText "pbzx-decode.py" ''
        import lzma
        import struct
        import sys

        XZ_MAGIC = b"\xfd7zXZ\x00"

        src = open(sys.argv[1], "rb")
        out = sys.stdout.buffer

        if src.read(4) != b"pbzx":
            sys.exit("not a pbzx stream")
        src.read(8)  # chunk window size, informational only

        while True:
            hdr = src.read(16)
            if not hdr:
                break
            if len(hdr) != 16:
                sys.exit("truncated pbzx chunk header")
            uncomp, comp = struct.unpack(">QQ", hdr)
            data = src.read(comp)
            if len(data) != comp:
                sys.exit("truncated pbzx chunk data")

            # comp == uncomp 的块按未压缩存储；防御性地非 xz 头也按原始处理。
            if comp == uncomp or not data.startswith(XZ_MAGIC):
                if len(data) != uncomp:
                    sys.exit("raw pbzx chunk size mismatch")
                out.write(data)
                continue

            written = 0
            buf = data
            while buf:
                dec = lzma.LZMADecompressor()
                piece = dec.decompress(buf)
                out.write(piece)
                written += len(piece)
                buf = dec.unused_data
            if written != uncomp:
                sys.exit("pbzx chunk decompressed size mismatch")
        out.flush()
      '';
    in
    pkgs.stdenv.mkDerivation {
      pname = "dingtalk";
      inherit version src meta;

      nativeBuildInputs = with pkgs; [
        _7zz
        python3
        cpio
      ];

      unpackPhase = ''
        runHook preUnpack
        set -o pipefail
        # dmg 里是 DingTalkInstaller.pkg（xar），Payload 为 pbzx 压缩的 cpio。
        7zz x -bd -o"dmg" "$src"
        7zz x -bd -o"pkg" "dmg/DingTalk For Mac/DingTalkInstaller.pkg" "DingTalk.pkg/Payload"
        python3 ${pbzxDecode} pkg/DingTalk.pkg/Payload | cpio -idm --quiet
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/Applications $out/bin
        cp -R Applications/DingTalk.app $out/Applications/DingTalk.app
        ln -s $out/Applications/DingTalk.app/Contents/MacOS/DingTalk $out/bin/dingtalk

        runHook postInstall
      '';

      # .app 带厂商代码签名（arm64 上必须保持有效），任何 fixup 都可能破坏它，
      # 因此整个 fixupPhase 直接跳过；bundle 内部依赖用 @rpath 相对定位。
      dontFixup = true;
    };
in
{
  perSystem =
    { system, ... }:
    let
      # 闭源免费分发（unfree）：自建 allowUnfree 的 pkgs，不依赖外层 flake 的配置
      #（与本仓库 napcat.nix 的做法一致），这样任何上下文都能直接 nix run。
      pkgs = import inputs.nixpkgs.outPath {
        inherit system;
        config.allowUnfree = true;
      };
    in
    lib.mkIf (sources ? ${system}) {
      packages.dingtalk-unwrapped =
        let
          inherit (sources.${system}) version url hash;
          src = pkgs.fetchurl { inherit url hash; };
        in
        if pkgs.stdenv.hostPlatform.isDarwin then
          mkDarwin { inherit pkgs src version; }
        else
          mkLinux { inherit pkgs src version; };
    };
}
