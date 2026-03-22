# Fix UPEK Fingerprint Scanner (Patches Reverted by System Update)

## Context

The UPEK TouchStrip fingerprint reader (USB `0483:2016`) stopped working because an automatic system update on **2026-03-21 20:25** upgraded `libfprint-2-2` and `libfprint-2-tod1` from the patched version (`~24.04.5`) to the official unpatched version (`~24.04.6`), overwriting the two-line fix in `upekts.c`. The packages were never pinned with `apt-mark hold`.

**Previous incident:** The first time we applied this patch (~March 11), the built `.deb` packages were broken — fprintd couldn't load the patched library, causing GDM to time out (error 127 on console). Reinstalling the official Ubuntu packages restored login. The likely cause was building with `dpkg-buildpackage -d` (skip dependency checks), which can produce a broken library if build deps are incomplete.

Journal logs confirm the same verify errors as before:
- `Response had wrong subcommand type` (bug 1: wrong buffer sent)
- `verify result abnormally short!` (bug 2: inverted error condition)

## Plan

### Step 0: Save official packages for rollback

Before touching anything, download the current working official `.deb` files so we can restore login if things go wrong:

```bash
mkdir -p ~/libfprint-rollback
cd ~/libfprint-rollback
apt download libfprint-2-2 libfprint-2-tod1
```

Also note the rollback command for emergencies (from TTY via Ctrl+Alt+F3):
```bash
sudo dpkg -i ~/libfprint-rollback/libfprint-2-2_*.deb ~/libfprint-rollback/libfprint-2-tod1_*.deb
sudo systemctl restart fprintd
```

### Step 1: Build patched packages (safely)

Update `fix-libfprint.sh` before running it:

1. **Remove the `-d` flag** from `dpkg-buildpackage` (line 52) — this was likely the cause of the previous broken build. Without `-d`, the build will fail early if dependencies are missing, rather than producing a broken library.

2. **Add `apt-mark hold`** after the `dpkg -i` step (after line 56) to prevent future auto-upgrade reversion.

3. **Add a library sanity check** after `dpkg -i` — verify the installed `.so` can be loaded:
   ```bash
   ldd /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep "not found"
   ```
   If any dependencies show "not found", immediately rollback.

Then run the script:
```bash
cd ~/Projects/libfprint-upek-fix
bash fix-libfprint.sh
```

### Step 2: Verify library health BEFORE restarting fprintd

After the `.deb` install but before restarting fprintd, confirm the library is healthy:

```bash
# Check no missing dependencies
ldd /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep "not found"

# Check fprintd can start
sudo systemctl restart fprintd
systemctl status fprintd
```

If fprintd fails to start → **immediately rollback** using the saved packages from Step 0.

### Step 3: Hold packages

```bash
sudo apt-mark hold libfprint-2-2 libfprint-2-tod1
apt-mark showhold | grep fprint
```

### Step 4: Test fingerprint verify

```bash
fprintd-verify $(whoami)
```

If verification fails, re-enroll:
```bash
fprintd-enroll -f right-index-finger $(whoami)
```

### Step 5: Test password login still works

**Before logging out of the current session**, open a second TTY (Ctrl+Alt+F3) and confirm you can log in with your password. Only then is it safe to log out / reboot.

## Files to modify

- `/home/laroy/Projects/libfprint-upek-fix/fix-libfprint.sh` — remove `-d` flag, add `apt-mark hold`, add library sanity check

## Verification checklist

1. `ldd /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep "not found"` — no missing deps
2. `systemctl status fprintd` — active, no errors
3. `dpkg -l | grep libfprint-2-2` — shows locally-built patched version
4. `apt-mark showhold` — lists both `libfprint-2-2` and `libfprint-2-tod1`
5. `fprintd-verify $(whoami)` — fingerprint scan succeeds
6. `journalctl -u fprintd --no-pager -n 20` — no "wrong subcommand type" errors
7. TTY password login works

## Emergency rollback

If GUI login breaks after applying the patch:
1. Switch to TTY: **Ctrl+Alt+F3**
2. Log in with username/password
3. Restore official packages:
   ```bash
   sudo dpkg -i ~/libfprint-rollback/libfprint-2-2_*.deb ~/libfprint-rollback/libfprint-2-tod1_*.deb
   sudo systemctl restart fprintd
   ```
4. Return to GUI: **Ctrl+Alt+F1**
