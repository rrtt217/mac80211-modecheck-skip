#!/bin/bash
# [已弃用] 由构建器 mac80211-modecheck-skip-builder 取代; 保留仅供未安装构建器时应急。
# 迁移后请勿再运行: 它会重新引入旧版 1.0 包, 与新版方案抢占同一模块文件。
# 原功能: 从 Koji 拉取与当前内核完全一致的内核源码/kernel-devel,
# 重新生成外部构建 Makefile 并应用补丁, 刷新 DKMS 包, 编译安装。
set -euo pipefail
echo ">> 提示: 若已安装构建器, 请改用 'sudo mac80211-modecheck-autoprep' (本脚本为旧方案)"

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="mac80211-modecheck-skip"
VERSION="1.0"
KREL="$(uname -r)"
ARCH="$(uname -m)"                         # 例如 x86_64
VER="${KREL%%-*}"                          # 例如 7.2.10
REL="${KREL#*-}"; REL="${REL%.${ARCH}}"    # 例如 200.fc44
BASE="https://kojipkgs.fedoraproject.org/packages/kernel/${VER}/${REL}"
WORK="${HERE}/work-reprep"

echo ">> 目标内核: ${KREL}  (Koji: ${VER}/${REL})"
mkdir -p "${WORK}" && cd "${WORK}"

echo ">> 下载源码 ..."
if [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' kernel.src.rpm 2>/dev/null)" = "${VER}-${REL}" ]; then
    echo ">> 已存在 ${VER}-${REL} 的源码 rpm, 跳过下载"
else
    curl -fL -o kernel.src.rpm "${BASE}/src/kernel-${VER}-${REL}.src.rpm"
fi
if rpm -q "kernel-devel-${KREL}" >/dev/null 2>&1; then
    echo ">> kernel-devel-${KREL} 已安装, 跳过下载/安装"
else
    if [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' kernel-devel.rpm 2>/dev/null)" != "${VER}-${REL}" ]; then
        curl -fL -o kernel-devel.rpm "${BASE}/${ARCH}/kernel-devel-${VER}-${REL}.${ARCH}.rpm"
    fi
    sudo dnf install -y ./kernel-devel.rpm
fi

echo ">> 解包并应用补丁 ..."
rm -f linux-*.tar.xz
rpm2cpio kernel.src.rpm | cpio -idmu --quiet
TARBALL="$(ls -1 linux-*.tar.xz 2>/dev/null | head -n1)"
[ -n "${TARBALL}" ] || { echo "!! SRPM 中未找到源码 tarball"; exit 1; }
tar -xJf "${TARBALL}" "linux-${VER}/net/mac80211"
rm -rf pkg-src && cp -r "linux-${VER}/net/mac80211" pkg-src && rm -rf pkg-src/tests

# 由新内核自带的 Makefile 生成外部构建版(自动跟随对象列表变化)
sed -e 's|^obj-$(CONFIG_MAC80211) += mac80211.o|obj-m += mac80211.o|' \
    -e '/^obj-y += tests\//d' \
    "linux-${VER}/net/mac80211/Makefile" > pkg-src/Makefile
grep -q '^obj-m += mac80211.o' pkg-src/Makefile || {
    echo "!! Makefile 生成失败(未匹配到 obj-\$(CONFIG_MAC80211) 行), 请人工检查上游 Makefile"; exit 1; }
cat >> pkg-src/Makefile <<'EOF'

KVER ?= $(if $(KERNELRELEASE),$(KERNELRELEASE),$(shell uname -r))
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
EOF

# 补丁路径为 a/net/mac80211/mlme.c -> 扁平化后需 -p3
patch -p3 -d pkg-src < "${HERE}/payload/patches/0001-skip-beacon-modechange-disconnect.patch"

echo ">> 刷新 DKMS 源码并编译安装 ..."
SRC="/usr/src/${PKG}-${VERSION}"
sudo dkms remove -m "${PKG}" -v "${VERSION}" --all 2>/dev/null || true
sudo rm -rf "${SRC}"
sudo mkdir -p "${SRC}/patches"
sudo cp "${HERE}/payload/dkms.conf" "${SRC}/dkms.conf"
sudo cp "${HERE}/payload/patches/0001-skip-beacon-modechange-disconnect.patch" "${SRC}/patches/"
sudo cp -r pkg-src/. "${SRC}/"
sudo sed -i "s|^BUILD_EXCLUSIVE_KERNEL=.*|BUILD_EXCLUSIVE_KERNEL=\"^$(printf '%s' "${KREL}" | sed 's/\./\\./g')\$\"|" "${SRC}/dkms.conf"
sudo dkms add     -m "${PKG}" -v "${VERSION}"
sudo dkms build   -m "${PKG}" -v "${VERSION}" -k "${KREL}"
sudo dkms install -m "${PKG}" -v "${VERSION}" -k "${KREL}"

echo ">> 完成。重载无线栈使补丁模块生效:"
echo "   nmcli radio wifi off"
echo "   sudo modprobe -r iwlmvm iwlwifi mac80211 && sudo modprobe iwlwifi"
echo "   nmcli radio wifi on"
