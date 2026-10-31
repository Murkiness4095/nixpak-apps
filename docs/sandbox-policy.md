# 沙盒模块约定

本仓库是通用 nixpak 沙盒集合。目标是让每个应用模块自包含，`common.nix` 只保留真正通用的隔离策略。

## common.nix 的边界

`common.nix` 只允许放**所有应用都成立**的内容：

- D-Bus 基础策略、portal 白名单
- XDG 目录重定向（`~/.var/app/<appId>/{config,data,cache}`）
- Wayland/PipeWire/Pulse socket、`/tmp` tmpfs
- `/dev/dri`、`/dev/snd`、`/dev/shm`
- 通用字体、GTK schema、基础 `/etc` 文件
- 通用 PATH、输入法、Electron/Wayland 环境变量

以下内容**禁止**放进 `common.nix`：

- 某个应用的托盘 SNI（`StatusNotifierItem-<pid>-1`）
- 某个应用的 D-Bus 名称（如 `com.usebottles.bottles`）
- 厂商专属设备（如 NVIDIA `/dev/nvidia*`）
- Wine/umu/Proton 专属路径（如 `/etc/zoneinfo`、`/run/opengl-driver-32`）
- 某个应用的数据目录、启动参数、文件选择器开关

判断规则：**只服务 1 个应用或 1 个厂商的配置，不进 common；至少 2 个互不相关应用都需要，才考虑 common。**

## 应用模块职责

每个 `<app>.nix` 自己负责：

- `app.package` / `app.binPath` / `flatpak.appId`
- 该应用的 D-Bus 策略和托盘 PID
- 该应用需要的设备、store path、Wine/Proton 路径
- 应用专属数据目录绑定
- 是否启用 `nixpakCommon.fileChooser.enable`
- 桌面项、图标、`meta.mainProgram`

已有例子：

| 配置 | 位置 |
|---|---|
| 托盘 `StatusNotifierItem-<pid>-1` | 各应用模块 |
| Bottles D-Bus 名称 | `bottles.nix` |
| NVIDIA `/dev/nvidia*` | `heroic.nix`、`bottles.nix`、`lutris.nix` |
| `/etc/zoneinfo`、`/run/opengl-driver-32` | Wine 相关模块 |
| `umu-launcher` store path | `bottles.nix` |

## 新增应用清单

1. 复制一个最接近的模块（Electron 参考 `vesktop.nix`/`heroic.nix`，Wine 参考 `bottles.nix`）。
2. 只写差异，`imports = [ ./common.nix ];`。
3. 如需托盘，用 launcher 固定 PID，并在本模块加 `dbus.policies."org.freedesktop.StatusNotifierItem-<pid>-1" = "own";`。
4. 只绑定该应用需要的目录/设备；不要整绑 `$HOME`。
5. 加入 `flake.nix` 的 `imports` 和 `README.md` 表格。
6. 构建验证：`nix build .#<app>`；能运行则再 `nix run .#<app>`。

## 包选择

| 应用 | 包 | 原因 |
|---|---|---|
| Heroic | `heroic-unwrapped` | nixpak 自己就是 wrapper，不需要 Steam runtime 包装 |
| Bottles | `bottles-unwrapped` | 避免 FHS wrapper 与 bwrap 叠加 |
| Lutris | `lutris` | nixpkgs 的 Lutris 入口 |

## 已知限制

- xdg-dbus-proxy 不支持通配符，托盘 SNI 只能逐 PID 放行。
- Wine 游戏如果需要额外驱动/前缀路径，必须在对应模块显式绑定。
- 沙盒不做出站网络过滤。
