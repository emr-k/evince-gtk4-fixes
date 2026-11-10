#!/usr/bin/env bash
# EXPERIMENTAL (known crash, see README). Fixes Ctrl + mouse wheel zoom in Evince 49 by rebuilding your distribution's
# Evince package with the patches in ./patches and installing it.
#
#   ./fix-scroll-zoom.sh
#
# Supported: Debian, Ubuntu and derivatives (apt); Fedora and derivatives (dnf).
# Anything else: see "Other distributions" in the README.
#
# Uses sudo for package installation. Read the script before running it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${WORK:-$HOME/evince-scroll-zoom-build}"
RUN="$BASE/run-$(date +%Y%m%d-%H%M%S)"   # every run starts from a fresh, unpatched source

PATCHES=("$HERE/patches/0001-ctrl-scroll-zoom.patch" "$HERE/patches/0002-zoom-center.patch" "$HERE/patches/0003-layout-while-loading.patch")

# For testing: SKIP_PATCHES="0003" ./fix-scroll-zoom.sh leaves out every patch
# whose file name contains one of the given words.
if [ -n "${SKIP_PATCHES:-}" ]; then
    kept=()
    for p in "${PATCHES[@]}"; do
        skip=0
        for word in $SKIP_PATCHES; do
            case "$(basename "$p")" in *"$word"*) skip=1 ;; esac
        done
        [ "$skip" = 1 ] || kept+=("$p")
    done
    PATCHES=("${kept[@]}")
    echo "Using patches: ${PATCHES[*]##*/}"
fi

for p in "${PATCHES[@]}"; do
    [ -f "$p" ] || { echo "Missing $p" >&2; exit 1; }
done

if [ -z "${I_UNDERSTAND:-}" ]; then
    echo "WARNING: these patches are experimental. On the machine they were tested on," >&2
    echo "Evince crashed within minutes of Ctrl + wheel zooming. See 'Known crash' in" >&2
    echo "the README. Trying Papers instead may be simpler." >&2
    echo "To continue anyway, run:  I_UNDERSTAND=1 $0" >&2
    exit 1
fi
[ -r /etc/os-release ] || { echo "Cannot detect the distribution (no /etc/os-release)." >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release

patch_failed() {
    echo >&2
    echo "A patch did not apply." >&2
    echo "Possible reasons: this Evince version is not affected (the file" >&2
    echo "libview/evince-view.ui exists only from Evince 49) or your distribution" >&2
    echo "already changed the same code." >&2
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
    mkdir -p "$RUN"
    cd "$RUN"
    sudo apt build-dep -y evince
    apt source evince
    local src p
    src="$(ls -d "$RUN"/evince-*/ | head -n 1)"
    cd "$src"
    for p in "${PATCHES[@]}"; do
        patch -p1 --dry-run < "$p" > /dev/null || patch_failed
        patch -p1 < "$p"
    done
    DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -b
    cd "$RUN"
    # dev, doc and debug-symbol packages are not needed
    sudo dpkg -i $(ls "$RUN"/*.deb | grep -v -e '-dev_' -e '-doc_' -e dbgsym)

    # WITH_DEBUG=1 ./fix-scroll-zoom.sh also installs the debug symbols of the
    # two libraries, so a crash backtrace shows function names.
    if [ -n "${WITH_DEBUG:-}" ]; then
        local dbg
        dbg=$(ls "$RUN"/libevview*dbgsym*.*deb "$RUN"/libevdocument*dbgsym*.*deb 2>/dev/null || true)
        if [ -n "$dbg" ]; then
            # shellcheck disable=SC2086
            sudo dpkg -i $dbg
        else
            echo "No debug-symbol packages found in $RUN." >&2
        fi
    fi
}

# ---------------------------------------------------------------- Fedora family
build_rpm() {
    local top="$RUN/rpmbuild" spec i n
    sudo dnf install -y rpm-build dnf-plugins-core
    sudo dnf builddep -y evince
    mkdir -p "$RUN" "$top"
    cd "$RUN"
    dnf download --source evince
    rpm --define "_topdir $top" -ivh "$RUN"/evince-*.src.rpm
    spec="$top/SPECS/evince.spec"

    # Register every patch (in reverse, so the final order is ascending) and
    # make sure the spec applies it.
    for ((i = ${#PATCHES[@]} - 1; i >= 0; i--)); do
        n=$((9001 + i))
        cp "${PATCHES[$i]}" "$top/SOURCES/"
        sed -i "0,/^Source0\?:.*/s//&\nPatch$n: $(basename "${PATCHES[$i]}")/" "$spec"
        if ! grep -q '^%autosetup' "$spec"; then
            sed -i "0,/^%setup.*/s//&\n%patch -P $n -p1/" "$spec"
        fi
    done
    sed -i '0,/^Release:.*/s/^\(Release:[[:space:]]*\)\(.*\)$/\1\2.scrollfix/' "$spec"

    # The prep step applies the patches; fail early and clearly if one does not
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
