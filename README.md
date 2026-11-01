# evince-gtk4-fixes

Fixes for three regressions in Evince 49 (the GTK 4 version), first seen on Ubuntu 26.04 LTS:

| Symptom | Fix | Needs a rebuild? |
|---|---|---|
| Ctrl + mouse wheel no longer zooms the document, zoom does not follow the cursor, and a fast zoom-out can leave the view on empty space | [`fix-scroll-zoom.sh`](fix-scroll-zoom.sh) | Yes, three small patches to Evince |
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

**Second problem: the zoom centre.** Once zooming works, `ev_view_scroll_event` still reads the zoom centre with `gdk_event_get_axis (event, GDK_AXIS_X / GDK_AXIS_Y, ...)`. In the GTK 4.22.4 source scroll events have no position: the default `get_position` returns `FALSE` and leaves the outputs untouched. In Evince, `x` and `y` are declared as `double x, y;` without a value, so the zoom centre is whatever happens to be in memory.

What was measured, on one machine (debug output of the zoom code, 261 zoom steps): before `0002`, the centre was `0.0` in every step, so zooming always anchored the top edge of the view instead of the point under the cursor. After `0002`, the centre followed the cursor (about 0 with the cursor at the top of the view, about 1000 at the bottom, in a view 1001 px high).

[`patches/0002-zoom-center.patch`](patches/0002-zoom-center.patch) takes the cursor position from the existing helper `ev_document_misc_get_pointer_position()` instead. The same call is already used elsewhere in `ev-view.c`.

Not confirmed: an undefined centre can also push the view to the very start or end of the document (the scroll position is clamped), which matches reports of "zooming sometimes jumps to the first or last page". That jump did not occur in the measurement run, so the patch is not proven to fix it. On the GitHub mirror's main branch (checked 2026-10-22) the affected lines were unchanged.

**Third problem: empty space after a fast zoom-out.** Zooming out quickly to the minimum could leave the view below the last page, showing nothing; scrolling up or typing a page number fixed it. Logging the layout code on one machine showed this:

- `ev_view_size_allocate` returns early while the view's `loading` flag is set. The flag is set while drawing a page whose image is not ready yet and is cleared only when that page is drawn again.
- During a fast zoom-out one such skipped layout happened. Nothing asked for another one, so the scroll range (`upper`) stayed at the old, much larger value while the document had shrunk (2809 against 1809 in one log). The scroll position could then move into the empty part.
- Evince 46.3 (GTK 3) only skips layout when there is no document. The `|| ev_view_is_loading (view)` part is new in 49.

[`patches/0003-layout-while-loading.patch`](patches/0003-layout-while-loading.patch) removes that extra condition. Test on the same machine: one run with fast zooming (about 400 zoom steps between 0.14 and 5.2, reaching the minimum zoom several times), and in every logged frame after startup (about 690) the scroll range matched the document height and the position never went past the end. Before the patch, each of the three logged runs that zoomed out quickly to the minimum ended in the stuck state (in the first one this was inferred from missing layout records, in the other two it was logged directly). That is one machine and one PDF, 14 pages, so treat it as encouraging, not proven. I do not know why the `loading` check was added; if you know of a case it protects against, please open an issue.

**What the script does**

- Debian family: enables `deb-src` in `ubuntu.sources` or `debian.sources`, installs build dependencies, runs `apt source evince`, applies the patch (dry run first), builds with `dpkg-buildpackage -us -uc -b` and installs the resulting `.deb` files with `dpkg -i`.
- Fedora family: installs build dependencies, downloads the source RPM, adds the patch to the spec file, tags the release as `.scrollfix`, builds with `rpmbuild` and installs with `dnf`.

Build files go to `~/evince-scroll-zoom-build` (override with `WORK=/some/dir`). The rebuilt packages keep the official version number (Debian family) or add `.scrollfix` to the release (Fedora family), so a newer official package replaces them on the next update.

**Going back.** Reinstall the official packages. On Debian or Ubuntu: `dpkg -l | grep -i evince`, then `sudo apt install --reinstall <those names>`. On Fedora: `sudo dnf distro-sync 'evince*'`.

**Upstream.** The problem is tracked in [evince#2131](https://gitlab.gnome.org/GNOME/evince/-/work_items/2131), linked to Debian bug #1127562. I could not open the related merge request and do not know whether it carries the same fix. On 2026-10-22, `evince-view.ui` was unchanged between `49.alpha` and the GitHub mirror's main branch.

**Zoom step size.** With a mouse wheel, zoom moves in steps of 20 % per notch. That is not part of this bug: Evince 46.3 (GTK 3) uses the same factor and the same logic. I tried an extra patch that scaled the factor by the wheel's movement and used 10 % steps; on one mouse it felt worse, so it is not included.

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
