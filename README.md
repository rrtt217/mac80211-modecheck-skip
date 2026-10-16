# mac80211-modecheck-skip

绕过校园 H3C AP 导致 Linux 客户端周期性断网的 mac80211 补丁模块，附自动构建器（Fedora / systemd / DKMS）。

## 背景

H3C 接入点偶尔会在 beacon 中把 VHT 能力短暂"回退"为 legacy，Linux mac80211 检测到
`AP appears to change mode (expected VHT, found legacy) in beacon` 后会强制断开连接，
引发反复重连风暴（每次中断数秒、日均数十次）。本仓库提供一个 5 行补丁：
**对 beacon 中的瞬时模式回退只记录日志（`ignoring`），不再断开**；
assoc/reassoc 响应中的能力不一致仍保持原断连行为。

## 内容

- `payload/` —— 核心补丁（`patches/`，5 行改动）与 `dkms.conf`（构建器打包材料）；
  各内核配套源码由构建器按内核版本从 Fedora Koji 自动获取
- `builder-rpm/` —— 自动构建器（systemd path/timer + DKMS）：安装一次后，
  当前及之后每个新内核都会自动从 Fedora Koji 拉取同版源码、打补丁并编译安装；
  失败自动跳过并在下次重试，不影响开机

## 安装

从 [Releases](../../releases) 下载 RPM，或本地构建（`cd builder-rpm && ./build-rpm.sh`）：

```bash
sudo dnf install mac80211-modecheck-skip-builder-*.rpm
# 重载无线栈使补丁立刻生效（不操作的话下次重启自行生效）
nmcli radio wifi off
sudo modprobe -r iwlmvm iwlwifi mac80211 && sudo modprobe iwlwifi
nmcli radio wifi on
```

查看状态：

```bash
journalctl -u mac80211-modecheck-prep.service -f   # 构建/安装日志
dkms status                                        # 各内核的模块状态
journalctl -k | grep 'change mode'                 # 应只看到 "ignoring"
```

## 卸载

```bash
sudo dnf remove mac80211-modecheck-skip-builder   # 自动移除并还原官方模块
```

## 说明

- 适用 Fedora 系（dnf + dkms + systemd）；需能访问 Fedora Koji 获取内核源码
- 本补丁规避的是客户端侧症状；根因在 AP 侧，建议同时向学校网络中心反馈
- License: GPL-2.0（见 [LICENSE](LICENSE)）
