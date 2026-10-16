# SPDX-License-Identifier: GPL-2.0
# Adapted from linux-7.2.7 net/mac80211/Makefile for external (DKMS) build.
# 改动: obj-$(CONFIG_MAC80211) -> obj-m, 去掉 obj-y += tests/ (KUnit 测试模块保持原版不变)

obj-m += mac80211.o

# mac80211 objects
mac80211-y := \
	main.o status.o \
	driver-ops.o \
	sta_info.o \
	wep.o \
	aead_api.o \
	wpa.o \
	scan.o offchannel.o \
	ht.o agg-tx.o agg-rx.o \
	vht.o \
	he.o \
	s1g.o \
	ibss.o \
	iface.o \
	link.o \
	rate.o \
	tkip.o \
	aes_cmac.o \
	aes_gmac.o \
	fils_aead.o \
	cfg.o \
	ethtool.o \
	rx.o \
	spectmgmt.o \
	tx.o \
	key.o \
	util.o parse.o \
	wme.o \
	chan.o ap.o \
	trace.o mlme.o \
	tdls.o \
	ocb.o \
	airtime.o \
	eht.o uhr.o nan.o

mac80211-$(CONFIG_MAC80211_LEDS) += led.o
mac80211-$(CONFIG_MAC80211_DEBUGFS) += \
	debugfs.o \
	debugfs_sta.o \
	debugfs_netdev.o \
	debugfs_key.o

mac80211-$(CONFIG_MAC80211_MESH) += \
	mesh.o \
	mesh_pathtbl.o \
	mesh_plink.o \
	mesh_hwmp.o \
	mesh_sync.o \
	mesh_ps.o

mac80211-$(CONFIG_PM) += pm.o

CFLAGS_trace.o := -I$(src)

rc80211_minstrel-y := \
	rc80211_minstrel_ht.o

rc80211_minstrel-$(CONFIG_MAC80211_DEBUGFS) += \
	rc80211_minstrel_ht_debugfs.o

mac80211-$(CONFIG_MAC80211_RC_MINSTREL) += $(rc80211_minstrel-y)

mac80211-y += wbrf.o

ccflags-y += -DDEBUG

KVER ?= $(if $(KERNELRELEASE),$(KERNELRELEASE),$(shell uname -r))
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
