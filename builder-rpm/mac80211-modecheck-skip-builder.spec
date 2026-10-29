Name:           mac80211-modecheck-skip-builder
Version:        1.0.1
Release:        1%{?dist}
Summary:        Auto-builder for a patched mac80211 that ignores AP mode-change flips

License:        GPL-2.0-only
BuildArch:      noarch

Requires:       dkms
Requires:       curl
Requires:       xz
Requires:       patch
Requires:       tar
Requires:       cpio
# systemd 单元的 ExecStart 目标（本机 rpm 无 systemd.attr 生成器, 需手写; 由包自身文件满足）
Requires:       /usr/local/sbin/mac80211-modecheck-autoprep
# nmcli 仅用于重载时保持无线电开关状态; 缺失时脚本降级运行(不影响核心功能)
Recommends:     NetworkManager
BuildRequires:  systemd-rpm-macros
%systemd_requires

Source0:        autoprep.sh
Source1:        dkms.conf
Source2:        0001-skip-beacon-modechange-disconnect.patch
Source3:        mac80211-modecheck-prep.service
Source4:        mac80211-modecheck-prep.path
Source5:        mac80211-modecheck-prep.timer

%description
Automatic builder for a patched mac80211 kernel module that ignores transient
"AP appears to change mode (expected VHT, found legacy) in beacon" flips
instead of force-disconnecting the client (workaround for H3C campus APs).

For every installed kernel missing the patched module it fetches the exact
matching kernel sources from Fedora's Koji, applies the patch and builds and
installs the module via DKMS. Building uses the official kernel-devel build
tree (auto-installed with kernel updates via the dkms dependency), falling
back to the Koji archive only for kernels dropped from the repos.

Triggered automatically when a kernel is installed (systemd path unit) and
retried at boot and hourly (systemd timer). The helper is idempotent and can
also be run manually:  sudo mac80211-modecheck-autoprep

%prep
# no-op: 无源码需要解包

%build
# no-op: 无需构建

%install
install -D -m 0755 %{SOURCE0} %{buildroot}/usr/local/sbin/mac80211-modecheck-autoprep
install -D -m 0644 %{SOURCE1} %{buildroot}/usr/local/share/mac80211-modecheck-skip/dkms.conf
install -D -m 0644 %{SOURCE2} %{buildroot}/usr/local/share/mac80211-modecheck-skip/patches/0001-skip-beacon-modechange-disconnect.patch
install -D -m 0644 %{SOURCE3} %{buildroot}%{_unitdir}/mac80211-modecheck-prep.service
install -D -m 0644 %{SOURCE4} %{buildroot}%{_unitdir}/mac80211-modecheck-prep.path
install -D -m 0644 %{SOURCE5} %{buildroot}%{_unitdir}/mac80211-modecheck-prep.timer

%post
systemctl daemon-reload >/dev/null 2>&1 || :
systemctl enable --now mac80211-modecheck-prep.timer mac80211-modecheck-prep.path >/dev/null 2>&1 || :
systemctl start --no-block mac80211-modecheck-prep.service >/dev/null 2>&1 || :

%preun
if [ "$1" -eq 0 ] ; then
    systemctl stop mac80211-modecheck-prep.service >/dev/null 2>&1 || :
    systemctl disable --now mac80211-modecheck-prep.timer mac80211-modecheck-prep.path >/dev/null 2>&1 || :
    /usr/local/sbin/mac80211-modecheck-autoprep --cleanup >/dev/null 2>&1 || :
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || :

%files
/usr/local/sbin/mac80211-modecheck-autoprep
/usr/local/share/mac80211-modecheck-skip/dkms.conf
/usr/local/share/mac80211-modecheck-skip/patches/0001-skip-beacon-modechange-disconnect.patch
%{_unitdir}/mac80211-modecheck-prep.service
%{_unitdir}/mac80211-modecheck-prep.path
%{_unitdir}/mac80211-modecheck-prep.timer

%changelog
* Thu Oct 29 2026 david - 1.0.1-1
- Wait for in-progress kernel installs (the path unit fires before
  modules.dep exists) and rescan; previously the build was delayed until
  the hourly timer
- Disable dkms AUTOINSTALL (template + enforced in generated configs) to
  silence harmless BUILD_EXCLUSIVE skip warnings on kernel updates
* Fri Oct 16 2026 david - 1.0-1
- Initial package: per-kernel auto-build of the patched mac80211 via DKMS
