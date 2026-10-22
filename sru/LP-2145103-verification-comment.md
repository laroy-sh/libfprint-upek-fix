I tested 1:1.94.7+tod1-0ubuntu5~24.04.9 from noble-proposed on real hardware. Verification passes.

System: Ubuntu 24.04.5 LTS (amd64), kernel 7.0.0-31-generic, fprintd 1.94.3-1
Device: Bus 003 Device 002: ID 0483:2016 STMicroelectronics Fingerprint Reader (UPEK TouchStrip)

Installed from noble-proposed:
  libfprint-2-2          1:1.94.7+tod1-0ubuntu5~24.04.9
  libfprint-2-tod1:amd64 1:1.94.7+tod1-0ubuntu5~24.04.9

Before the update, with the stock Noble package, enrolment completed but no verify ever matched.

Results, following the [Test Plan]:

1. I deleted the existing prints and enrolled again with fprintd-enroll -f right-index-finger: enroll-completed.
2-3. fprintd-verify with the enrolled finger, swiped 10 times with a few seconds between attempts:
     9/10 verify-match, 1/10 verify-no-match (a poor swipe). No errors.
4. Negative test, swiping a finger that was not enrolled: verify-no-match. No crash and no hang.
5. PAM: fingerprint auth is enabled in common-auth (pam_fprintd, with password fallback). I cleared cached credentials and ran "sudo -k; sudo true". It prompted "Swipe your right index finger across the fingerprint reader", and one swipe authenticated without a password prompt.

One more observation: in a first run, my script started each fprintd-verify immediately after the previous one finished. 4 of the 11 attempts in that run (3 with the enrolled finger, 1 negative) ended in verify-unknown-error. fprintd logged "async msg read failed: transfer timed out" followed by "Device reported an error during verify: transfer timed out". With a short pause between attempts, the timeouts did not happen at all (the results above). The patch does not change the USB transfer or timeout handling in upekts.c, so as far as I can tell this is driver or device timing that the fix does not affect. Each of those failures was an error, not a false match. With pam_fprintd's password fallback, an error like this leads to the password prompt. I'm mentioning it for completeness.

Tagging verification-done-noble.
