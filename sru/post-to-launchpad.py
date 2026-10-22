#!/usr/bin/env python3
"""Post SRU comment + debdiff + ubuntu-sponsors subscription to LP #2145103.

Run against the system Python (which has python3-launchpadlib):

    /usr/bin/python3 sru/post-to-launchpad.py              # dry-run (default)
    /usr/bin/python3 sru/post-to-launchpad.py --post       # actually post

The first --post run opens a browser for a one-time OAuth authorisation.
Credentials are cached under ~/.cache/launchpadlib/ so subsequent runs
are non-interactive.
"""

import argparse
import sys
from pathlib import Path

BUG_ID = 2145103
REPO = Path(__file__).resolve().parent
COMMENT_FILE = REPO / "LP-2145103-sru-comment.md"
DEBDIFF_FILE = REPO / "libfprint_1.94.7+tod1-0ubuntu5~24.04.9.debdiff"
COMMENT_SUBJECT = (
    "SRU request: backport upstream fix for UPEK TouchStrip verify "
    "(rebased debdiff, ~24.04.9)"
)
ATTACHMENT_DESCRIPTION = (
    "SRU debdiff vs. 1:1.94.7+tod1-0ubuntu5~24.04.8 (noble-proposed) — adds "
    "debian/patches/upekts-fix-verify.patch (upstream cdc22b45 / MR !415, "
    "first released in libfprint 1.94.9) and bumps changelog to ~24.04.9."
)
ATTACHMENT_COMMENT = (
    "Attaching rebased SRU debdiff against 1:1.94.7+tod1-0ubuntu5~24.04.8\n"
    "(noble-proposed), replacing the earlier ~24.04.7 debdiff whose version\n"
    "was taken by an unrelated upload (per the automated sponsoring\n"
    "review). The patch content is unchanged. See the SRU template comment\n"
    "above for Impact, Test Plan, and Where-problems-could-occur sections.\n\n"
    "Verified: dpkg-source -x on the rebuilt .dsc applies the patch\n"
    "cleanly; both hunks land at lines 1246 and 1298 of\n"
    "libfprint/drivers/upekts.c."
)
SPONSORS_TEAM = "ubuntu-sponsors"
CONSUMER_NAME = "libfprint-upek-fix-sru"


def preview(comment: str, debdiff: bytes) -> None:
    print(f"Target:    https://bugs.launchpad.net/ubuntu/+source/libfprint/+bug/{BUG_ID}")
    print(f"Comment:   {COMMENT_FILE.name}  ({len(comment):,} B, {comment.count(chr(10))} lines)")
    print(f"           subject: {COMMENT_SUBJECT!r}")
    print(f"Debdiff:   {DEBDIFF_FILE.name}  ({len(debdiff):,} B)")
    print(f"           is_patch=True, content_type=text/x-diff")
    print(f"Subscribe: {SPONSORS_TEAM}")
    print()
    print("--- comment head (first 12 lines) ---")
    for line in comment.splitlines()[:12]:
        print(f"  {line}")
    print("  [...]")
    print("--- comment tail (last 5 lines) ---")
    for line in comment.splitlines()[-5:]:
        print(f"  {line}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--post", action="store_true",
                    help="Actually post. Default is dry-run.")
    args = ap.parse_args()

    if not COMMENT_FILE.exists():
        print(f"missing: {COMMENT_FILE}", file=sys.stderr)
        return 2
    if not DEBDIFF_FILE.exists():
        print(f"missing: {DEBDIFF_FILE}", file=sys.stderr)
        return 2

    comment = COMMENT_FILE.read_text()
    debdiff = DEBDIFF_FILE.read_bytes()

    preview(comment, debdiff)
    print()

    if not args.post:
        print("DRY RUN — nothing was sent. Re-run with --post to submit.")
        return 0

    from launchpadlib.launchpad import Launchpad
    from launchpadlib.credentials import UnencryptedFileCredentialStore

    cachedir = Path.home() / ".cache" / "launchpadlib"
    cachedir.mkdir(parents=True, exist_ok=True)
    creds_path = cachedir / f"{CONSUMER_NAME}-credentials"

    print(f"Authenticating to Launchpad (first run opens a browser).")
    print(f"  credentials file: {creds_path}")
    lp = Launchpad.login_with(
        CONSUMER_NAME,
        service_root="production",
        launchpadlib_dir=str(cachedir),
        version="devel",
        allow_access_levels=["WRITE_PUBLIC"],
        credential_store=UnencryptedFileCredentialStore(str(creds_path)),
    )
    print(f"  authenticated as {lp.me.name} ({lp.me.display_name})")

    bug = lp.bugs[BUG_ID]
    print(f"  bug:    {bug.web_link}")
    print(f"  title:  {bug.title}")
    if bug.bug_tasks:
        t = bug.bug_tasks[0]
        print(f"  task:   {t.bug_target_display_name} — status={t.status}")

    print("Posting SRU template comment...")
    msg = bug.newMessage(subject=COMMENT_SUBJECT, content=comment)
    print(f"  posted: {getattr(msg, 'web_link', msg)}")

    print("Attaching debdiff...")
    bug.addAttachment(
        comment=ATTACHMENT_COMMENT,
        data=debdiff,
        filename=DEBDIFF_FILE.name,
        content_type="text/x-diff",
        description=ATTACHMENT_DESCRIPTION,
        is_patch=True,
    )
    print("  attachment uploaded")

    print(f"Subscribing {SPONSORS_TEAM}...")
    sponsors = lp.people[SPONSORS_TEAM]
    bug.subscribe(person=sponsors)
    print(f"  {SPONSORS_TEAM} subscribed")

    print()
    print(f"Done. Check: {bug.web_link}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
