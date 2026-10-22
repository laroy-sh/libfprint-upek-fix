(Rebased submission: the previously attached debdiff used version
~24.04.7, which has since been taken by an unrelated upload in the
archive, as flagged by the automated sponsoring review. The attached
debdiff is regenerated against 1:1.94.7+tod1-0ubuntu5~24.04.8 (currently
in noble-proposed) with version ~24.04.9. The patch itself is unchanged.)

[Impact]

UPEK TouchStrip fingerprint readers (USB ID 0483:2016) cannot be used for
authentication on Ubuntu 24.04 LTS. Enrolment appears to succeed but every
subsequent verify call via fprintd-verify (and therefore every PAM/GDM/sudo
fingerprint authentication attempt) times out or reports "verification
failed". Affected users can enrol but never authenticate, making the
hardware effectively useless for its intended purpose. This matches the
symptoms tracked upstream in freedesktop.org libfprint issue #321.

The root cause is two defects in libfprint/drivers/upekts.c in the version
shipped by Noble (currently 1:1.94.7+tod1-0ubuntu5~24.04.7 in
noble-updates; the defects are equally present in ~24.04.8 in
noble-proposed):

1. verify_start_sm_run_state passes the raw enrolled fingerprint data
   (data, data_len) to alloc_send_cmd28_transfer instead of the composed
   verify message (msg, msg_len) that the function has just built with
   verify_hdr. The device receives a malformed frame and never produces
   a match.

2. do_verify_stop has an inverted condition — "if (error && error->domain
   == FP_DEVICE_RETRY)" where it should be "if (!error || error->domain
   == FP_DEVICE_RETRY)" — so even when the hardware does return a
   successful match (error == NULL), the result is never delivered to
   fprintd. Every scan appears to fail even when it succeeded.

Both defects are fixed upstream in commit cdc22b45 (MR !415), merged
2025-02-13 and first released in libfprint 1.94.9 (2025-02-20). Debian
already ships the fix via new-upstream 1:1.94.10-1 and has seen no
regression reports. Noble remains on 1.94.7+tod1 and therefore still
carries both bugs.

[Test Plan]

Pre-conditions:
 * System with a UPEK TouchStrip reader; verify with "lsusb | grep 0483:2016".
 * fprintd and libpam-fprintd installed.
 * PAM fingerprint *not* configured for sudo/login during the reproduction
   step, to avoid locking yourself out of the session. Re-enable after
   verification.

Reproduce on stock Noble libfprint-2-2 (1:1.94.7+tod1-0ubuntu5~24.04.7):

 1. fprintd-enroll $(whoami)
    — follow prompts; enrolment completes successfully ("enroll-completed").
 2. fprintd-verify $(whoami)
    — place the enrolled finger on the reader.
 3. Observed bad behaviour: every swipe returns "verify-no-match" or
    a timeout even with the correctly enrolled finger. Ten consecutive
    swipes produce zero matches.

Verify the fix (with the SRU package installed):

 1. fprintd-enroll $(whoami)
    (re-enrolment is recommended because old enrolments were captured
    through the broken verify path and may not be fully compatible.)
 2. fprintd-verify $(whoami)
    — swipe the enrolled finger.
 3. Expected good behaviour: "verify-match" within about a second on the
    correct finger. Ten consecutive swipes of the enrolled finger should
    produce approximately ten matches.
 4. Negative test: fprintd-verify with a non-enrolled finger still
    returns "verify-no-match" (it does not match everything, and it
    does not crash or hang).
 5. Re-enable PAM fingerprint for sudo or login (pam-auth-update
    --enable fprintd) and confirm interactive authentication works
    end-to-end.

The submitter has been running this exact patch on a production
Ubuntu 24.04 desktop since 2026-03-21 without incident.

[Where problems could occur]

The patch is strictly confined to libfprint/drivers/upekts.c. No shared
code, no other drivers, no ABI. The upekts driver serves only UPEK
TouchStrip devices (USB IDs 0483:2016, 147e:2016, 147e:2020, 147e:3000,
147e:5000). Any regression would be limited to those devices.

The plausible failure modes are narrow:

 * Hunk 1 (verify_start_sm_run_state): the fix replaces a pointer to
   raw enrolled data with a pointer to the correctly framed verify
   message. A regression here would mean a device that previously
   tolerated a malformed frame now fails — but since the previous code
   path never produced a match on any hardware, there is no working
   baseline to regress from.

 * Hunk 2 (do_verify_stop): the fix extends the "report result
   immediately" branch from "retry-class error only" to "success OR
   retry-class error". The prior success path (retry error) is
   preserved byte-for-byte; the fix only adds the missing success
   branch. A regression would require a scenario where reporting a
   successful match synchronously (rather than via the deferred
   data->error path) is itself incorrect — none has been observed
   upstream, in Debian, or locally over ~5 weeks of daily use.

 * Re-enrolment may be required on first use after the update because
   existing enrolments were captured through the broken verify path.
   This is documented in the test plan and does not affect other
   fingerprint drivers.

The change has been shipping upstream since libfprint 1.94.9
(2025-02-20) and in Debian unstable since 1:1.94.8-1 (Feb 2025) with
no regression reports filed in either tracker against the upekts
driver.

[Other Info]

 * Upstream commit:
   https://gitlab.freedesktop.org/libfprint/libfprint/-/commit/cdc22b45
 * Upstream merge request (merged 2025-02-13):
   https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/415
 * First upstream release with fix: libfprint 1.94.9 (2025-02-20).
 * Upstream bug report:
   https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/321
 * Debian ships the fix via new-upstream 1:1.94.10-1; no distro patch
   is carried.
 * Reference backport, rollback artefacts, and user-facing documentation:
   https://github.com/laroy-sh/libfprint-upek-fix

A minimal debdiff against the newest source package
(1:1.94.7+tod1-0ubuntu5~24.04.8, noble-proposed) is attached as
libfprint_1.94.7+tod1-0ubuntu5~24.04.9.debdiff. It adds a single
DEP-3-annotated patch (debian/patches/upekts-fix-verify.patch) to
the existing quilt series and bumps debian/changelog with an
SRU-style version (~24.04.9). dpkg-source --extract of the resulting
.dsc applies the patch cleanly; both hunks land at the expected
lines in libfprint/drivers/upekts.c (1246 and 1298).
