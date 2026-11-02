# nixpak sandboxes

Sandboxed Linux desktop applications built with
[nixpak](https://github.com/nixpak/nixpak) (bubblewrap + xdg-dbus-proxy).

## Apps

| 包 | appId | 数据路径 |
|---|---|---|
| `wechat` | `com.tencent.WeChat` | `~/.var/app/com.tencent.WeChat/xwechat` |
| `wechat-uos` | `com.tencent.WeChatUOS` | `~/.var/app/com.tencent.WeChatUOS/{xwechat,xwechat_files,config,data,cache}` |
| `qq` | `com.tencent.QQ` | `~/.var/app/com.tencent.QQ/config/QQ` |
| `dingtalk` | `com.alibabainc.dingtalk` | `~/.var/app/com.alibabainc.dingtalk/config/{DingTalk,com.alibabainc.dingtalk}` |
| `feishu` | `com.bytedance.feishu` | `~/.var/app/com.bytedance.feishu/{config,cache}/LarkShell` |
| `telegram` | `org.telegram.desktop` | `~/.var/app/org.telegram.desktop/data/TelegramDesktop` |
| `nheko` | `io.github.NhekoReborn.Nheko` | `~/.var/app/io.github.NhekoReborn.Nheko/{config,data,cache}` |
| `vesktop` | `dev.vencord.Vesktop` | `~/.var/app/dev.vencord.Vesktop/config/{vesktop,discord}` |
| `heroic` | `com.heroicgameslauncher.hgl` | `~/.var/app/com.heroicgameslauncher.hgl/{config,data,cache}` (游戏装到 `~/Games`) |
| `bottles` | `com.usebottles.bottles` | `~/.var/app/com.usebottles.bottles` (Bottles/游戏装到 `~/Bottles`/`~/Games`) |

所有应用的 `Downloads` 统一指向宿主真实 `~/Downloads`。

## Usage

本地：

```bash
nix run .#<app>
```

不克隆直接体验：

```bash
nix run github:Murkiness4095/nixpak-apps#<app>
# 远端缓存旧时：
nix run --refresh github:Murkiness4095/nixpak-apps#<app>
```

## Structure

```
flake.nix
common.nix            # 全部沙盒的公共隔离策略
lib/fonts.nix         # 沙盒专用字体环境生成器
<app>.nix             # 每个沙盒应用一个模块
unwrapped/dingtalk.nix # 钉钉原始打包（deb/dmg -> 应用树）
```

## Isolation (common.nix)

- 宿主 `$HOME` / `~/.config` / `~/.local/share` 默认不可见；
- XDG 目录重定向到 `~/.var/app/<appId>/{config,data,cache}`；
- 不整绑 `$XDG_RUNTIME_DIR`，只绑 wayland / at-spi / gvfsd / dconf 等具体 socket；
- `/tmp` 使用私有 tmpfs；
- 严格 Wayland-only（`QT_QPA_PLATFORM=wayland`、`ELECTRON_OZONE_PLATFORM_HINT=wayland`、`NIXOS_OZONE_WL=1`），不挂 X11；
- D-Bus 通过 xdg-dbus-proxy，portal 只放行白名单，**FileChooser 默认关闭**；
- `/dev/dri`、`/dev/snd`、`/dev/shm` 可用，摄像头按应用单独加 `/dev/video0`；
- 字体默认由 `lib/fonts.nix` 生成（LXGW WenKai Screen 优先 + Noto 兜底 + 去 ASCII 的彩色 emoji）；Telegram 绑定宿主 `/etc/fonts`。

## Tray

Qt/Electron 的 SNI 名字是 `org.kde.StatusNotifierItem-<pid>-1` / `org.freedesktop.StatusNotifierItem-<pid>-1`，沙盒内 PID 都从 2 开始，因此用常驻子进程占位错开 PID：

| 应用 | SNI 名 |
|---|---|
| 飞书 | `-2-1` |
| 钉钉 | `-4-1` |
| QQ | `-5-1` |
| Telegram | `-6-1` |
| Nheko | `-8-1` |
| Vesktop | `-9-1` |
| 微信（内层 FHS） | `-10-2` |

xdg-dbus-proxy 不支持通配符，因此在 `common.nix` 里逐 PID 放行。

## Known limitations

1. **网络不做出站过滤**：映射目录内的文件可见即可上传；敏感数据不要放进映射目录。
2. **剪贴板**：沙盒应用与宿主共享剪贴板。
3. **FileChooser 关闭**：文件只能从 Downloads 选；开启 portal FileChooser 会带来目录递归授权风险。
4. **不绑 runtime**：需要可写 `XDG_RUNTIME_DIR` 的应用可能异常；目前实测主应用正常。
5. **无 X11**：任何只支持 xcb 的功能会不可用；不建议为敏感应用重新打开 X11。
6. **钉钉**：Linux 版只有浅色主题。

## Maintenance

- 新增应用：复制一个模块，`imports = [ ./common.nix ];`，只写差异。
- `packages.<app>` 都设置了 `meta.mainProgram`，`nix run .#<app>` 可直接启动；新增应用时保持与 `app.binPath` 的可执行文件名一致。
- 调字体：改 `lib/fonts.nix` 或应用里 `fonts.mk` 参数。
- 升级钉钉：改 `unwrapped/dingtalk.nix` 的 `sources`。
- `nixpakCommon.fileChooser.enable` 可按应用单独放行 FileChooser portal（钉钉文件选择器 workaround）。

## Consuming from nix-config

```nix
inputs.nixpak-apps.url = "github:Murkiness4095/nixpak-apps";
inputs.nixpak-apps.inputs.nixpkgs.follows = "nixpkgs";
```

`follows` 可选但推荐：写了就版本统一，不写就用 nixpak-apps 自己的 nixpkgs。

### Overlay（推荐）

```nix
nixpkgs.overlays = [ inputs.nixpak-apps.overlays.default ];
```

所有沙盒应用在 `pkgs.nixpakApps` 下：

```nix
# hjem
hjem.users.${user}.packages = [
  pkgs.nixpakApps.wechat
  pkgs.nixpakApps.qq
  pkgs.nixpakApps.dingtalk
];

# NixOS
environment.systemPackages = [ pkgs.nixpakApps.wechat ];
```

### Modules

```nix
imports = [ inputs.nixpak-apps.nixosModules.default ];       # environment.systemPackages
# Home Manager 用户：
imports = [ inputs.nixpak-apps.homeManagerModules.default ]; # home.packages
```

模块在非 Linux 上为空操作，Darwin 不会报错。

### 自定义沙盒应用

```nix
common = inputs.nixpak-apps.lib.nixpak.common;
fonts  = inputs.nixpak-apps.lib.nixpak.fonts;
```

`common.nix` 和 `lib/fonts.nix` 已带递归扫描守卫，可安全被 flake-parts 自动 import。

> 沙盒应用只支持 Linux（`x86_64-linux` / `aarch64-linux`）；Darwin 上 `nixpakApps` 为空，不会报错。
