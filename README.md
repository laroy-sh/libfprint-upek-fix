# libfprint-upek-fix

Fix for UPEK TouchStrip fingerprint reader (USB `0483:2016`) failing to verify on **Ubuntu 24.04**.

## Symptoms

- `fprintd-verify` always times out or returns "verification failed"
- Enrollment succeeds but login/sudo via fingerprint never works
- Other fingerprint readers work fine on the same system

## Root cause

Two bugs in `libfprint/drivers/upekts.c` (present in Ubuntu's packaged `libfprint 1.94.7`):

1. **Wrong buffer** in `verify_start_sm_run_state`: the function was sending the raw enrolled data (`data, data_len`) to the device instead of the composed verify message (`msg, msg_len`), so the device received a malformed command and could never match.

2. **Inverted error condition** in `do_verify_stop`: `if (error && error->domain == FP_DEVICE_RETRY)` should be `if (!error || error->domain == FP_DEVICE_RETRY)`. The success result was never reported to fprintd.

Backport of upstream commit `cdc22b45`.

## Affected hardware

- UPEK TouchStrip — USB ID `0483:2016`

Check yours with: `lsusb | grep -i upek`

## Fix

```bash
bash fix-libfprint.sh
```

The script will:
1. Install build dependencies
2. Download the Ubuntu `libfprint` source package
3. Apply both patches to `upekts.c`
4. Build and install patched `.deb` packages
5. Restart `fprintd`

Then test with:
```bash
fprintd-verify $(whoami)
```

## After fixing

Re-enroll your finger if needed:
```bash
fprintd-enroll -f right-index-finger $(whoami)
```

Clean up build dependencies (~170 packages):
```bash
sudo apt remove --autoremove dpkg-dev devscripts build-essential \
  libglib2.0-dev libgusb-dev libgudev-1.0-dev libnss3-dev gi-docgen \
  gir1.2-gusb-1.0 gobject-introspection libgirepository1.0-dev
```

## Files

| File | Description |
|------|-------------|
| `fix-libfprint.sh` | Automated fix script |
| `upekts-fix-verify.patch` | The two-line patch for reference |

## Related

- Upstream commit: `cdc22b45` in [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint)
- Ubuntu Launchpad bug: [#2145103](https://bugs.launchpad.net/ubuntu/+source/libfprint/+bug/2145103)
