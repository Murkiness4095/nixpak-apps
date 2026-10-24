# 共享的沙盒字体环境生成器。
# 只保留实际用到的参数：name、aliases（按族名强制映射）、minimal（旧版 fontconfig）。
args:
if args ? self || !(args ? pkgs) then { } else
let
  pkgs = args.pkgs;
  primaryName = "LXGW WenKai Screen";
  primary = [ pkgs.lxgw-wenkai-screen ];
  primaryFile = "${pkgs.lxgw-wenkai-screen}/share/fonts/truetype/LXGWWenKaiScreen.ttf";
  fallbacks = [ pkgs.noto-fonts ];

  # Noto Color Emoji 去掉 ASCII 0x20-0x7E，避免它用宽字格接管数字/符号
  emojiNoAscii = pkgs.runCommandLocal "noto-color-emoji-no-ascii" {
    nativeBuildInputs = [ pkgs.python3Packages.fonttools ];
  } ''
    mkdir -p $out/share/fonts/noto
    python3 - "$out" <<'PY'
    import sys
    from fontTools.ttLib import TTFont
    src = "${pkgs.noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf"
    dst = sys.argv[1] + "/share/fonts/noto/NotoColorEmoji.ttf"
    font = TTFont(src)
    for table in font["cmap"].tables:
        for cp in [c for c in table.cmap if 0x20 <= c <= 0x7E]:
            del table.cmap[cp]
    font.save(dst)
    PY
  '';

  mk =
    { name, aliases ? [ ], minimal ? false }:
    let
      dirs = primary ++ [ emojiNoAscii ] ++ fallbacks;
      extraRules = pkgs.lib.concatMapStringsSep "\n" (family: ''
        <match target="pattern">
          <test name="family" qual="any"><string>${family}</string></test>
          <edit name="family" mode="assign" binding="strong"><string>${primaryName}</string></edit>
        </match>
      '') aliases;
      fontsConf = pkgs.writeText "nixpak-fonts.conf" ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          ${pkgs.lib.concatMapStringsSep "\n" (d: "<dir>${d}</dir>") dirs}
          <match target="pattern">
            <edit name="family" mode="prepend" binding="strong">
              <string>${primaryName}</string>
            </edit>
          </match>
          ${extraRules}
          <cachedir>${pkgs.makeFontsCache {
            inherit (pkgs) fontconfig;
            fontDirectories = dirs;
          }}</cachedir>
          ${pkgs.lib.optionalString minimal ''<cachedir prefix="xdg">fontconfig</cachedir>''}
        </fontconfig>
      '';
    in
    if minimal then
      pkgs.runCommandLocal name { } ''
        mkdir -p $out/etc/fonts
        cp ${fontsConf} $out/etc/fonts/fonts.conf
      ''
    else
      pkgs.runCommandLocal name { } ''
        mkdir -p $out/etc/fonts
        cp -rL ${pkgs.fontconfig.out}/etc/fonts/conf.d $out/etc/fonts/conf.d
        chmod -R u+w $out/etc/fonts/conf.d
        cp ${fontsConf} $out/etc/fonts/conf.d/00-nixpak-fonts.conf
        ${pkgs.gnused}/bin/sed '/dejavu-fonts/d' \
          ${pkgs.fontconfig.out}/etc/fonts/fonts.conf > $out/etc/fonts/fonts.conf
      '';
in
{
  inherit primaryFile primaryName emojiNoAscii mk;
}
