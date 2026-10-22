#!/usr/bin/env bash
# Fixes Ctrl + mouse wheel zoom in Evince 49 by rebuilding your distribution's
# Evince package with patches/0001-ctrl-scroll-zoom.patch and installing it.
#
# Supported: Debian, Ubuntu and derivatives (apt); Fedora and derivatives (dnf).
# Anything else: see "Other distributions" in the README.
#
# Uses sudo for package installation. Read the script before running it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/patches/0001-ctrl-scroll-zoom.patch"
WORK="${WORK:-$HOME/evince-scroll-zoom-build}"

[ -f "$PATCH" ] || { echo "Missing $PATCH" >&2; exit 1; }
[ -r /etc/os-release ] || { echo "Cannot detect the distribution (no /etc/os-release)." >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release

patch_failed() {
    echo >&2
    echo "The patch did not apply." >&2
    echo "Possible reasons: this Evince version is not affected (the file" >&2
    echo "libview/evince-view.ui exists only from Evince 49), your distribution" >&2
    echo "already fixed it, or the source was patched by an earlier run." >&2
    exit 1
}

# ---------------------------------------------------------------- Debian family
enable_deb_src() {
    local found=0 f
    for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
        [ -f "$f" ] || continue
        found=1
        grep -q '^Types:.*deb-src' "$f" || sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$f"
    done
    if [ "$found" = 0 ] && ! grep -rqs '^deb-src' /etc/apt/sources.list /etc/apt/sources.list.d; then
        echo "No deb-src entries found. Enable source repositories in your apt" >&2
        echo "configuration (e.g. add 'deb-src' lines to /etc/apt/sources.list) and rerun." >&2
        exit 1
    fi
}

build_deb() {
    enable_deb_src
    sudo apt update
    sudo apt install -y build-essential fakeroot
    mkdir -p "$WORK"
    cd "$WORK"
    sudo apt build-dep -y evince
    apt source evince
    local src
    src="$(ls -d "$WORK"/evince-*/ | head -n 1)"
    cd "$src"
    patch -p1 --dry-run < "$PATCH" > /dev/null || patch_failed
    patch -p1 < "$PATCH"
    DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -b
    cd "$WORK"
    # dev, doc and debug-symbol packages are not needed
    sudo dpkg -i $(ls "$WORK"/*.deb | grep -v -e '-dev_' -e '-doc_' -e dbgsym)
}

# ---------------------------------------------------------------- Fedora family
build_rpm() {
    local top="$WORK/rpmbuild" spec
    sudo dnf install -y rpm-build dnf-plugins-core
    sudo dnf builddep -y evince
    mkdir -p "$WORK" "$top"
    cd "$WORK"
    dnf download --source evince
    rpm --define "_topdir $top" -ivh "$WORK"/evince-*.src.rpm
    spec="$top/SPECS/evince.spec"
    cp "$PATCH" "$top/SOURCES/"

    # Register the patch, make sure it gets applied, and mark the release
    sed -i '0,/^Source0\?:.*/s//&\nPatch9001: 0001-ctrl-scroll-zoom.patch/' "$spec"
    if ! grep -q '^%autosetup' "$spec"; then
        sed -i '0,/^%setup.*/s//&\n%patch -P 9001 -p1/' "$spec"
    fi
    sed -i '0,/^Release:.*/s/^\(Release:[[:space:]]*\)\(.*\)$/\1\2.scrollfix/' "$spec"

    # Prep step applies the patch; fail early and clearly if it does not
    rpmbuild --define "_topdir $top" -bp "$spec" || patch_failed
    rpmbuild --define "_topdir $top" -bb "$spec"
    # devel, doc and debug packages are not needed
    sudo dnf install -y $(find "$top/RPMS" -name '*.rpm' \
        ! -name '*-devel-*' ! -name '*-doc-*' ! -name '*debuginfo*' ! -name '*debugsource*')
}

# ---------------------------------------------------------------- dispatch
family="${ID:-} ${ID_LIKE:-}"
if echo "$family" | grep -qwE 'debian|ubuntu'; then
    build_deb
elif echo "$family" | grep -qwE 'fedora|rhel'; then
    build_rpm
else
    echo "Unsupported distribution: ${PRETTY_NAME:-unknown}." >&2
    echo "See 'Other distributions' in the README for the manual steps." >&2
    exit 1
fi

echo "Done. Close all Evince windows and open a PDF again."
