#!/bin/bash
# mac80211-modecheck-skip 自动构建器(由 mac80211-modecheck-skip-builder RPM 提供)
#
# 作用: 为每个缺少"补丁版 mac80211"的内核构建并安装 DKMS 模块。
#   - 构建树: 优先使用官方 kernel-devel(系统已装, 内核更新时由 dkms 依赖自动带装);
#             仓库已下架的内核回退 Fedora 官方构建系统 Koji 的归档 rpm
#   - 源码:   从 Koji 拉取与目标内核完全同版的源码 rpm(net/mac80211 与 Fedora 构建一致)
#   - 构建:   dkms, 版本号 = 内核 release, 多个内核的实例互不影响
# 幂等, 可反复运行; 由 systemd path/timer 触发, 也可手动执行:
#   sudo mac80211-modecheck-autoprep             # 准备所有已装内核
#   sudo mac80211-modecheck-autoprep --cleanup   # 移除本包全部版本(还原官方模块)
set -euo pipefail

PKG="mac80211-modecheck-skip"
STATE_DIR="/var/lib/$PKG"
CACHE_DIR="/var/cache/$PKG"
PAYLOAD_DIR="/usr/local/share/$PKG"
PATCH_FILE="$PAYLOAD_DIR/patches/0001-skip-beacon-modechange-disconnect.patch"
BASE_URL="https://kojipkgs.fedoraproject.org/packages/kernel"
ARCH="$(uname -m)"
RUN_KREL="$(uname -r)"

log()  { echo "[$PKG] $*"; }
warn() { echo "[$PKG] 警告: $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "需要 root 权限运行" >&2; exit 1; }
mkdir -p "$STATE_DIR" "$CACHE_DIR"
[[ -f "$PATCH_FILE" ]] || { warn "补丁文件缺失: $PATCH_FILE"; exit 1; }

reload_wifi() {
	# 保持无线电开关状态, 重载无线栈以把新模块换入内存
	local state
	state="$(nmcli -t radio wifi 2>/dev/null || echo enabled)"
	nmcli radio wifi off >/dev/null 2>&1 || true
	modprobe -r iwlmvm iwlwifi >/dev/null 2>&1 || true
	modprobe -r mac80211-tests mac80211_tests >/dev/null 2>&1 || true
	modprobe -r mac80211 >/dev/null 2>&1 || true
	modprobe iwlwifi >/dev/null 2>&1 || true
	if [[ "$state" == "enabled" ]]; then
		nmcli radio wifi on >/dev/null 2>&1 || true
	fi
	log "无线栈已重载"
}

covered() {	# $1=krel: 该内核已有任意版本的补丁模块 installed?
	dkms status 2>/dev/null | grep -F ", $1," | grep -q ': installed'
}

ensure_kernel_devel() {	# $1=krel
	local krel="$1" ver rel drpm
	[[ -e "/lib/modules/$krel/build/Makefile" ]] && return 0
	ver="${krel%%-*}"; rel="${krel#*-}"; rel="${rel%.$ARCH}"
	log "$krel: 尝试安装官方 kernel-devel"
	if dnf install -y "kernel-devel-$krel" >/dev/null 2>&1; then
		[[ -e "/lib/modules/$krel/build/Makefile" ]] && return 0
	fi
	# 仓库已下架的内核: 回退 Koji 归档(与仓库内容同源)
	drpm="$CACHE_DIR/kernel-devel-$ver-$rel.$ARCH.rpm"
	if [[ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$drpm" 2>/dev/null)" != "$ver-$rel" ]]; then
		curl -fL --retry 3 --retry-delay 5 -o "$drpm" \
			"$BASE_URL/$ver/$rel/$ARCH/kernel-devel-$ver-$rel.$ARCH.rpm" || return 1
	fi
	dnf install -y "$drpm" >/dev/null 2>&1 || return 1
	[[ -e "/lib/modules/$krel/build/Makefile" ]]
}

prep_kernel() {	# $1=krel; 返回: 0=本次装好 3=已覆盖 1=失败
	local krel="$1" ver rel srcrpm work srcdir
	if covered "$krel"; then
		log "$krel: 已有补丁模块, 跳过"
		return 3
	fi
	ver="${krel%%-*}"; rel="${krel#*-}"; rel="${rel%.$ARCH}"

	ensure_kernel_devel "$krel" || { warn "$krel: kernel-devel 不可得, 跳过"; return 1; }

	srcrpm="$CACHE_DIR/kernel-$ver-$rel.src.rpm"
	if [[ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$srcrpm" 2>/dev/null)" != "$ver-$rel" ]]; then
		log "$krel: 下载同版源码 rpm (Koji)"
		curl -fL --retry 3 --retry-delay 5 -o "$srcrpm" \
			"$BASE_URL/$ver/$rel/src/kernel-$ver-$rel.src.rpm" \
			|| { warn "$krel: 源码下载失败(网络不可达?), 稍后自动重试"; return 1; }
	fi

	log "$krel: 组装源码并打补丁"
	work="$(mktemp -d "/var/tmp/$PKG-$krel.XXXXXX")"
	srcdir="/usr/src/$PKG-$krel"
	if ! ( cd "$work" \
		&& rpm2cpio "$srcrpm" | cpio -idmu --quiet \
		&& tar -xJf "linux-$ver.tar.xz" "linux-$ver/net/mac80211" ); then
		warn "$krel: 源码解包失败"; rm -rf "$work"; return 1
	fi

	rm -rf "$srcdir"; mkdir -p "$srcdir/patches"
	cp -r "$work/linux-$ver/net/mac80211/." "$srcdir/"
	rm -rf "$srcdir/tests"
	sed -e 's|^obj-$(CONFIG_MAC80211) += mac80211.o|obj-m += mac80211.o|' \
	    -e '/^obj-y += tests\//d' \
	    "$work/linux-$ver/net/mac80211/Makefile" > "$srcdir/Makefile"
	if ! grep -q '^obj-m += mac80211.o' "$srcdir/Makefile"; then
		warn "$krel: Makefile 生成失败(上游格式变化?)"; rm -rf "$work" "$srcdir"; return 1
	fi
	cat >> "$srcdir/Makefile" <<'WRAPEOF'

KVER ?= $(if $(KERNELRELEASE),$(KERNELRELEASE),$(shell uname -r))
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
WRAPEOF
	if ! patch -p3 -d "$srcdir" < "$PATCH_FILE"; then
		warn "$krel: 补丁未干净应用(内核源码已变动?), 跳过该内核"
		rm -rf "$work" "$srcdir"; return 1
	fi
	cp "$PAYLOAD_DIR/dkms.conf" "$srcdir/dkms.conf"
	sed -i "s|^BUILD_EXCLUSIVE_KERNEL=.*|BUILD_EXCLUSIVE_KERNEL=\"^$(printf '%s' "$krel" | sed 's/\./\\./g')\$\"|" "$srcdir/dkms.conf"
	cp "$PATCH_FILE" "$srcdir/patches/"
	rm -rf "$work"

	log "$krel: DKMS 构建 (需要几分钟)"
	dkms remove -m "$PKG" -v "$krel" --all >/dev/null 2>&1 || true
	dkms add -m "$PKG" -v "$krel" >/dev/null 2>&1 \
		|| { warn "$krel: dkms add 失败"; return 1; }
	dkms build -m "$PKG" -v "$krel" -k "$krel" >/dev/null 2>&1 \
		|| { warn "$krel: 编译失败, 详见 /var/lib/dkms/$PKG/$krel/build/make.log"; return 1; }
	dkms install -m "$PKG" -v "$krel" -k "$krel" >/dev/null 2>&1 \
		|| { warn "$krel: dkms install 失败"; return 1; }
	log "$krel: 安装完成"
	return 0
}

do_prep() {
	local d k rc running_installed=0
	for d in /lib/modules/*/; do
		k="${d%/}"; k="${k##*/}"
		[[ -f "/lib/modules/$k/modules.dep" ]] || continue
		rc=0
		prep_kernel "$k" || rc=$?
		if [[ $rc -eq 0 && "$k" == "$RUN_KREL" ]]; then
			running_installed=1
		fi
	done
	if [[ $running_installed -eq 1 ]] \
		&& lsmod | grep -q '^mac80211' \
		&& systemctl is-active --quiet NetworkManager; then
		reload_wifi || true
	fi
	log "本轮结束"
}

do_cleanup() {
	local v
	log "移除 $PKG 的全部 DKMS 版本(官方模块将自动还原)"
	while read -r v; do
		[[ -n "$v" ]] || continue
		dkms remove -m "$PKG" -v "$v" --all >/dev/null 2>&1 || true
		log "已移除 $PKG/$v"
	done < <(dkms status -m "$PKG" 2>/dev/null | sed -n "s|^$PKG/\([^,]*\),.*|\1|p" | sort -u)
	if lsmod | grep -q '^mac80211' && systemctl is-active --quiet NetworkManager; then
		reload_wifi || true
	fi
	log "清理完成"
}

case "${1:-prep}" in
	--cleanup)
		exec 9>"$STATE_DIR/.lock"; flock -w 900 9 || { warn "等待其他实例超时"; exit 1; }
		do_cleanup
		;;
	prep|"")
		exec 9>"$STATE_DIR/.lock"; flock -n 9 || { log "已有实例在运行, 退出"; exit 0; }
		do_prep
		;;
	*)
		echo "用法: $0 [--cleanup]" >&2; exit 2 ;;
esac
