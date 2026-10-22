# evince-gtk4-fixes

Fixes for two regressions in Evince 49 (the GTK 4 version), first seen on Ubuntu 26.04 LTS:

| Symptom | Fix | Needs a rebuild? |
|---|---|---|
| Ctrl + mouse wheel no longer zooms the document | [`fix-scroll-zoom.sh`](fix-scroll-zoom.sh) | Yes, one line in Evince |
| Page thumbnails in the sidebar are tiny (about 11×16 px) | [`fix-thumbnails.sh`](fix-thumbnails.sh) | No, one CSS rule |

The two fixes are independent. Use either or both.

## Quick start

```bash
git clone <this repository>
cd evince-gtk4-fixes

./fix-thumbnails.sh        # seconds, no root; undo with: ./fix-thumbnails.sh remove
./fix-scroll-zoom.sh       # rebuilds and installs your distribution's Evince (uses sudo)
```

Close all Evince windows and open a PDF again afterwards. Read the scripts before running them; they are short.

## Which distributions

| Distribution | Thumbnails | Scroll zoom |
|---|---|---|
| Ubuntu 26.04 | Tested | Tested by hand with the same commands the script runs; the script itself has not been run end to end |
| Debian (Evince 49 builds) | Untested, same mechanism | Script supports it, untested |
| Fedora and derivatives | Untested, same mechanism | Script supports it, untested |
| Others (Arch, NixOS, ...) | Same mechanism | See [Other distributions](#other-distributions) |

If you try it somewhere, please open an issue with your distribution, Evince version (`evince --version`) and GTK version, and whether it worked.

## Scroll zoom: details

**Only Evince 49 is affected.** The file involved, `libview/evince-view.ui`, does not exist in the 48.x releases I checked (48.0 to 48.4), and the patch does not apply to them. If your Evince is older, you most likely do not have this bug, and the script will stop with a message.

**Cause.** `ev_view_scroll_event` in `libview/ev-view.c` already implements Ctrl + wheel zoom. The `GtkEventControllerScroll` that calls it is declared in `evince-view.ui` without `flags`. In GTK 4.22.4 the default is `GTK_EVENT_CONTROLLER_SCROLL_NONE`, and the controller returns early when neither the vertical nor the horizontal flag is set (`gtk/gtkeventcontrollerscroll.c`), so the handler never runs.

**Fix.** [`patches/0001-ctrl-scroll-zoom.patch`](patches/0001-ctrl-scroll-zoom.patch) adds `<property name="flags">both-axes</property>`. It applies cleanly to the upstream `49.alpha` tag.

**What the script does**

- Debian family: enables `deb-src` in `ubuntu.sources` or `debian.sources`, installs build dependencies, runs `apt source evince`, applies the patch (dry run first), builds with `dpkg-buildpackage -us -uc -b` and installs the resulting `.deb` files with `dpkg -i`.
- Fedora family: installs build dependencies, downloads the source RPM, adds the patch to the spec file, tags the release as `.scrollfix`, builds with `rpmbuild` and installs with `dnf`.

Build files go to `~/evince-scroll-zoom-build` (override with `WORK=/some/dir`). The rebuilt packages keep the official version number (Debian family) or add `.scrollfix` to the release (Fedora family), so a newer official package replaces them on the next update.

**Going back.** Reinstall the official packages. On Debian or Ubuntu: `dpkg -l | grep -i evince`, then `sudo apt install --reinstall <those names>`. On Fedora: `sudo dnf distro-sync 'evince*'`.

**Upstream.** The problem is tracked in [evince#2131](https://gitlab.gnome.org/GNOME/evince/-/work_items/2131), linked to Debian bug #1127562. I could not open the related merge request and do not know whether it carries the same fix. On 2026-10-22, `evince-view.ui` was unchanged between `49.alpha` and the GitHub mirror's main branch.

## Thumbnails: details

**Cause.** The sidebar draws thumbnails with a `GtkCellRendererPixbuf`. It reserves the full thumbnail size (100 px wide), but when drawing, `gtk_icon_helper_paintable_snapshot` in `gtk/gtkiconhelper.c` limits the image to the icon size from CSS, 16 px by default. A portrait A4 page squeezed into 16 px of height is about 11 px wide, which is what you see. This was read from GTK 4.22.4; I did not check other GTK versions.

**Fix.** [`fix-thumbnails.sh`](fix-thumbnails.sh) adds this rule, between marker comments so it can be removed cleanly, to `~/.config/gtk-4.0/gtk.css`:

```css
evsidebarthumbnails iconview { -gtk-icon-size: 1000px; }
```

It only matches Evince's thumbnail sidebar. Commands: `./fix-thumbnails.sh` (install), `./fix-thumbnails.sh status`, `./fix-thumbnails.sh remove`.

Distribution packagers and Evince developers can use [`patches/thumbnail-size-for-packagers.patch`](patches/thumbnail-size-for-packagers.patch), which puts the same rule into `shell/evince.css`.

## Other distributions

Apply `patches/0001-ctrl-scroll-zoom.patch` to your distribution's Evince 49 source and rebuild the package the way you normally do. For example, on Arch add the patch to `source=()` and apply it with `patch -Np1` in `prepare()`. If the patch does not apply, make the edit by hand: add `<property name="flags">both-axes</property>` inside the `GtkEventControllerScroll` object in `libview/evince-view.ui`.

To try a build without installing it:

```bash
meson setup build && ninja -C build
mkdir -p /tmp/evb
find build/backend \( -name '*.so' -o -name '*.evince-backend' \) -exec ln -sf "$PWD/{}" /tmp/evb/ \;
EV_BACKENDS_DIR=/tmp/evb ./build/shell/evince some.pdf
```

Without `EV_BACKENDS_DIR`, a build-tree Evince looks in `/usr/local/lib/...`, finds no backends and cannot open PDFs.

## License

- The scripts and this documentation are released under the [MIT License](LICENSE).
- The files in `patches/` are changes to Evince and stay under Evince's own license, GPL-2.0-or-later.
