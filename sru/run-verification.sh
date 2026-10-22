#!/usr/bin/env bash
# Run the LP #2145103 test plan against the installed libfprint and log the
# results for the verification comment. Run as your normal user (no sudo).
#
# Usage: [SKIP_ENROLL=1] bash sru/run-verification.sh [swipes]   (default 10)
set -uo pipefail

SWIPES=${1:-10}
FINGER=right-index-finger
LOG="$(dirname "$0")/verification-$(date +%Y%m%d-%H%M).log"

START=$(date +%s)

exec > >(tee "$LOG") 2>&1

echo "== LP #2145103 verification, $(date -Is)"
lsb_release -ds
uname -r
lsusb | grep 0483:2016 || { echo "UPEK TouchStrip 0483:2016 not found"; exit 1; }
dpkg -l libfprint-2-2 libfprint-2-tod1 fprintd | tail -3
echo

if [ -n "${SKIP_ENROLL:-}" ]; then
    echo "== Step 1: skipped (SKIP_ENROLL set), using existing enrolment"
else
    echo "== Step 1: re-enrol $FINGER (old prints deleted first)"
    fprintd-delete "$USER" || true
    fprintd-enroll -f "$FINGER" "$USER" || { echo "enrolment failed"; exit 1; }
fi
echo

echo "== Step 2-3: $SWIPES verify attempts with the enrolled finger"
matches=0
for i in $(seq 1 "$SWIPES"); do
    read -rp "-- attempt $i/$SWIPES: press Enter, then swipe $FINGER... " _
    echo "   $(date +%T)"
    out=$(fprintd-verify -f "$FINGER" "$USER" 2>&1)
    echo "$out" | grep -E "verify-" | tail -1
    echo "$out" | grep -q "verify-match" && matches=$((matches + 1))
    sleep 3
done
echo "RESULT positive: $matches/$SWIPES matched"
echo

echo "== Step 4: negative test, swipe a DIFFERENT (non-enrolled) finger"
read -rp "Press Enter, then swipe a non-enrolled finger... " _
echo "   $(date +%T)"
out=$(fprintd-verify -f "$FINGER" "$USER" 2>&1)
echo "$out" | grep -E "verify-" | tail -1
if echo "$out" | grep -q "verify-no-match"; then
    echo "RESULT negative: no-match (expected)"
else
    echo "RESULT negative: UNEXPECTED, see output above"
fi
echo
echo "== fprintd journal for this run"
journalctl -u fprintd --since "@$START" --no-pager -o short-precise 2>&1 | grep -v systemd
echo
echo "Log saved to $LOG"
echo "Step 5: confirm sudo/login fingerprint auth works end-to-end by hand."
