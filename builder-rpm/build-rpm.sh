#!/bin/bash
# 构建 mac80211-modecheck-skip-builder RPM (无需 root)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$HERE/rpmbuild"
rm -rf "$TOP"
mkdir -p "$TOP"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}
cp "$HERE/autoprep.sh"                                                     "$TOP/SOURCES/"
cp "$HERE/../payload/dkms.conf"                                            "$TOP/SOURCES/"
cp "$HERE/../payload/patches/0001-skip-beacon-modechange-disconnect.patch" "$TOP/SOURCES/"
cp "$HERE/units/mac80211-modecheck-prep.service"                           "$TOP/SOURCES/"
cp "$HERE/units/mac80211-modecheck-prep.path"                              "$TOP/SOURCES/"
cp "$HERE/units/mac80211-modecheck-prep.timer"                             "$TOP/SOURCES/"
cp "$HERE/mac80211-modecheck-skip-builder.spec"                            "$TOP/SPECS/"
rpmbuild --define "_topdir $TOP" -bb "$TOP/SPECS/mac80211-modecheck-skip-builder.spec"
echo
echo "== 产物 =="
ls -la "$TOP"/RPMS/noarch/
