# nixpak sandboxes

基于 [nixpak](https://github.com/nixpak/nixpak)（bubblewrap + xdg-dbus-proxy）的桌面应用沙盒。
本地入口：`nix run .#<app>`。
不克隆直接体验：`nix run github:Murkiness4095/nixpak-apps#<app>`（远端缓存旧时加 `--refresh`）。

当前包含：

| 包 | 说明 |
|---|---|
| `wechat` | 微信（主实例） |
| `wechat-uos` | 微信 UOS 版（第二个账号） |
| `qq` | QQ |
| `dingtalk` | 钉钉 |
| `feishu` | 飞书 |
| `telegram` | Telegram Desktop |
| `nheko` | Nheko（Matrix） |
| `vesktop` | Vesktop（Discord 第三方客户端） |

## 结构

```
flake.nix
common.nix            # 全部沙盒的公共隔离策略
lib/fonts.nix         # 沙盒专用字体环境生成器
<app>.nix             # 每个沙盒应用一个模块（wechat、qq、dingtalk、feishu…）
unwrapped/dingtalk.nix # 钉钉原始打包（deb -> 应用树）
```

每个应用模块只包含：

- `app.package` / `app.binPath` / `flatpak.appId`
- 应用数据映射（大部分已改为 common 的 `~/.var/app`）
- 应用字体绑定（`/etc/fonts`）
- 启动包装（PID 占位、内置字体补丁、日志过滤等差异）

## 公共隔离策略（common.nix）

- **空根**：宿主 `$HOME`、`~/.config`、`~/.local/share` 默认不可见。
- **XDG 重定向**：沙盒内 `~/.config`、`~/.local/share`、`~/.cache` 指向
  `~/.var/app/<appId>/{config,data,cache}`。
- **不整绑 runtime**：不绑定宿主 `$XDG_RUNTIME_DIR`，只绑 wayland / at-spi /
  gvfsd / dconf 等具体 socket；未绑定的路径由 bwrap 创建挂载点。
- **私有 tmpfs `/tmp`**：不挂宿主 `/tmp`。
- **Wayland-only**：`QT_QPA_PLATFORM=wayland`、`ELECTRON_OZONE_PLATFORM_HINT=wayland`、
  `NIXOS_OZONE_WL=1`；不挂 X11 socket。
- **D-Bus**：xdg-dbus-proxy，portal 只放行
  Introspectable / OpenURI / Settings / Notification / Screenshot / ScreenCast / Request；
  **FileChooser 默认关闭**。
- **设备**：`/dev/dri`、`/dev/snd`、`/dev/shm`；摄像头按应用单独加 `/dev/video0`。
- **外链**：`NIXOS_XDG_OPEN_USE_PORTAL=1`，`xdg-utils` 进 PATH。
- **基础文件**：`/bin/sh`、`/etc/os-release`、`/etc/passwd`、`/etc/machine-id` 等。
- **字体**：默认由 `lib/fonts.nix` 生成（LXGW WenKai Screen 优先 + Noto 兜底 + 去 ASCII 的彩色 emoji）；
  Telegram 不使用自定义字体，直接绑定宿主 `/etc/fonts`。

## 应用数据

除特别注明外，Downloads 均为宿主真实 `~/Downloads`。

| 应用 | appId | 数据路径 |
|---|---|---|
| 微信 | `com.tencent.WeChat` | `~/.var/app/com.tencent.WeChat/xwechat` |
| 微信 UOS | `com.tencent.WeChatUOS` | `~/.var/app/com.tencent.WeChatUOS/{xwechat,xwechat_files,config,data,cache}` |
| QQ | `com.tencent.QQ` | `~/.var/app/com.tencent.QQ/config/QQ` |
| 钉钉 | `com.alibabainc.dingtalk` | `~/.var/app/com.alibabainc.dingtalk/config/{DingTalk,com.alibabainc.dingtalk}` |
| 飞书 | `com.bytedance.feishu` | `~/.var/app/com.bytedance.feishu/{config,cache}/LarkShell` |
| Telegram | `org.telegram.desktop` | `~/.var/app/org.telegram.desktop/data/TelegramDesktop` |
| Nheko | `io.github.NhekoReborn.Nheko` | `~/.var/app/io.github.NhekoReborn.Nheko/{config,data,cache}` |
| Vesktop | `dev.vencord.Vesktop` | `~/.var/app/dev.vencord.Vesktop/config/{vesktop,discord}` |


## 托盘

Qt/AppIndicator 的 SNI 名字是 `org.kde.StatusNotifierItem-<pid>-1`，沙盒内 PID 都为 2，
因此用常驻子进程占位错开：

| 应用 | SNI 名 |
|---|---|
| 飞书 | `-2-1` |
| 钉钉 | `-4-1` |
| QQ | `-5-1` |
| Telegram | `-6-1` |
| Nheko | `-8-1` |
| Vesktop | `-9-1` |
| 微信（内层 FHS） | `-10-2` |

纯 Wayland 下使用 SNI 托盘（不需要 X11）。Qt 应用用 `org.kde.StatusNotifierItem-*`，
Electron 用 `org.freedesktop.StatusNotifierItem-<pid>-1`；xdg-dbus-proxy 不支持通配符，
因此在 common.nix 里逐个 PID 放行。
QQ / Nheko / UOS 是否显示托盘还取决于应用自己的设置（QQ 设置里开启托盘；Nheko `window\tray=true`）。

## 已知限制

1. **网络不做出站过滤**：映射目录内的文件可见即可上传；敏感数据不要放进映射目录。
2. **剪贴板**：沙盒应用与宿主共享剪贴板。
3. **FileChooser 关闭**：文件只能从 Downloads 选；开启 portal FileChooser 会带来目录递归授权风险。
4. **不绑 runtime**：需要可写 `XDG_RUNTIME_DIR` 的应用可能异常；目前实测主应用正常。
5. **无 X11**：任何只支持 xcb 的功能会不可用；不建议为敏感应用重新打开 X11。
6. **钉钉**：Linux 版只有浅色主题。

## 维护

- 新增应用：复制一个模块，`imports = [ ./common.nix ];`，只写差异。
- `packages.<app>` 都设置了 `meta.mainProgram`，`nix run .#<app>` 可直接启动；新增应用时保持与 `app.binPath` 的可执行文件名一致。
- 调字体：改 `lib/fonts.nix` 或应用里 `fonts.mk` 参数。
- 升级钉钉：改 `unwrapped/dingtalk.nix` 的 `sources`。
