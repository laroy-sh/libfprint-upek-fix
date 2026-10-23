# libfprint-upek-fix

Fix for UPEK TouchStrip fingerprint reader (USB `0483:2016`) failing to verify on **Ubuntu 24.04**.

> **Fixed in Ubuntu.** The upstream fix shipped to `noble-updates` on 2026-10-22 as
> `libfprint 1:1.94.7+tod1-0ubuntu5~24.04.9` through a Stable Release Update
> ([LP #2145103](https://bugs.launchpad.net/bugs/2145103)). You no longer need the
> script below. See [Getting the fix](#getting-the-fix).

## Getting the fix

If you never ran `fix-libfprint.sh`, a normal upgrade is enough:

```bash
sudo apt update && sudo apt upgrade
```

If you did run it, release the hold first so apt can replace your locally built packages:

```bash
sudo apt-mark unhold libfprint-2-2 libfprint-2-tod1
sudo apt update && sudo apt upgrade
sudo systemctl restart fprintd
```

Check that you have the fixed version:

```bash
apt policy libfprint-2-2    # Installed: 1:1.94.7+tod1-0ubuntu5~24.04.9 or later
fprintd-verify $(whoami)
```

Ubuntu rolls out updates in phases, so `apt upgrade` may hold the package back for a few days
("deferred due to phasing"). To install it right away:

```bash
sudo apt install libfprint-2-2=1:1.94.7+tod1-0ubuntu5~24.04.9 libfprint-2-tod1=1:1.94.7+tod1-0ubuntu5~24.04.9
```

Your existing enrollments keep working. Once you are on the official package you can delete this
repo's `rollback/` directory and any build dependencies the script installed (see below).

## Symptoms

- `fprintd-verify` always times out or returns "verification failed"
- Enrollment succeeds but login/sudo via fingerprint never works
- Other fingerprint readers work fine on the same system

## Root cause

Two bugs in `libfprint/drivers/upekts.c` (present in Ubuntu's packaged `libfprint 1.94.7`):

1. **Wrong buffer** in `verify_start_sm_run_state`: the function was sending the raw enrolled data (`data, data_len`) to the device instead of the composed verify message (`msg, msg_len`), so the device received a malformed command and could never match.

2. **Inverted error condition** in `do_verify_stop`: `if (error && error->domain == FP_DEVICE_RETRY)` should be `if (!error || error->domain == FP_DEVICE_RETRY)`. The success result was never reported to fprintd.

Backport of upstream commit [`cdc22b45`](https://gitlab.freedesktop.org/libfprint/libfprint/-/commit/cdc22b45), merged via [MR !415](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/415) and first released in libfprint **v1.94.9** (2025-02-20). Ubuntu 24.04 ships `1.94.7+tod1`, so the fix was backported to that version: first by the script in this repo, then officially through the SRU.

## Affected hardware

- UPEK TouchStrip — USB ID `0483:2016`

Check yours with: `lsusb | grep -i upek`

## Workaround (historical, before the SRU)

Kept for reference. On an up-to-date Ubuntu 24.04 system, use the official package instead.

```bash
bash fix-libfprint.sh
```

The script will:
1. Install build dependencies
2. Download the Ubuntu `libfprint` source package
3. Apply both patches to `upekts.c`
4. Build and install patched `.deb` packages
5. Verify library dependencies are intact
6. **Hold both packages** with `apt-mark hold` to prevent auto-upgrades from reverting the fix
7. Restart `fprintd`

Then test with:
```bash
fprintd-verify $(whoami)
```

## After running the workaround

Re-enroll your finger if needed:
```bash
fprintd-enroll -f right-index-finger $(whoami)
```

Clean up build dependencies (~170 packages):
```bash
sudo apt remove --autoremove dpkg-dev devscripts build-essential debhelper \
  libglib2.0-dev libgusb-dev libgudev-1.0-dev libnss3-dev gi-docgen \
  gir1.2-gusb-1.0 gobject-introspection libgirepository1.0-dev \
  gtk-doc-tools libcairo2-dev umockdev libglib2.0-doc libgusb-doc
```

## If the held packages get upgraded

Upgrading to `~24.04.9` or later is now the fix, not a regression. If the hold was released and
apt installed the official package, you are done. Check with `apt policy libfprint-2-2`.

## Emergency rollback

If GUI login stops working after applying the fix:

1. Switch to a TTY: **Ctrl+Alt+F3**
2. Log in with your password
3. Restore the official packages:
```bash
sudo dpkg -i ~/Projects/libfprint-upek-fix/rollback/*.deb
sudo systemctl restart fprintd
```

> The `rollback/` directory contains official Ubuntu `.deb` files downloaded before patching. Re-populate with `apt download libfprint-2-2 libfprint-2-tod1` if needed.

## Files

| File | Description |
|------|-------------|
| `fix-libfprint.sh` | Automated fix script |
| `upekts-fix-verify.patch` | The two-line patch for reference |
| `rollback/` | Official Ubuntu `.deb` files for emergency rollback |
| `sru/` | SRU materials: the debdiff, Launchpad comments, and hardware verification scripts and logs |

## Related

- Upstream merge request: [libfprint!415 "upekts fixes"](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/415) (merged 2025-02-13)
- Upstream commit: [`cdc22b45`](https://gitlab.freedesktop.org/libfprint/libfprint/-/commit/cdc22b45) ("upekts: fix verify")
- First upstream release with fix: [v1.94.9](https://gitlab.freedesktop.org/libfprint/libfprint/-/releases/v1.94.9) (2025-02-20)
- Ubuntu Launchpad bug: [#2145103](https://bugs.launchpad.net/ubuntu/+source/libfprint/+bug/2145103) (Fix Released in noble-updates, 2026-10-22)
