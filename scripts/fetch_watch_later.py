#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = ["yt-dlp"]
# ///
"""
Fetch your YouTube Watch Later playlist and write it as a markdown note.

YouTube restricted the Watch Later playlist in 2016 and it has had no public
API since, so the only remaining read path is the cookies of a browser you are
already signed in with. That is what `yt-dlp --cookies-from-browser` does, and
it is why this script has to run on your own machine rather than on a server or
inside a container: a YouTube cookie is a Google cookie, so handing a browser
profile to an automated environment hands it your whole Google account.

If something downstream needs this list, give it the FILE this writes rather
than the credentials that produced it.

This script only reads. yt-dlp cannot write to Watch Later and nothing here
tries to — no videos are removed, reordered or marked watched.

Usage:

    uv run ~/justscripts/scripts/fetch_watch_later.py --browser firefox
    just watch-later firefox                     # same thing via the justfile
    just watch-later brave ~/some/other/folder   # explicit output directory

Writes `watch-later-<YYYY-MM-DD>.md` into the output directory (default: the
current directory): a front-matter block with the date and video count, then
one `- [title](url) — channel, m:ss` line per video, in Watch Later order.

Gotchas, both of which cost time the first run:

  * Pass the browser you are actually signed into YouTube on. `firefox` is the
    default because it is yt-dlp's own convention, not because it is likely to
    be right for you.

  * On macOS a Chromium-family browser (Chrome, Brave, Vivaldi, Edge) encrypts
    its cookie values with a key held in your login Keychain, and reading that
    key needs an interactive approval. Run this from a normal terminal session,
    as yourself. From anywhere that cannot prompt — a cron/launchd job, a CI
    runner, an agent session — you get this, in this order:

        WARNING: find-generic-password failed
        WARNING: cannot decrypt v10 cookies: no key found
        ERROR: [youtube:tab] WL: YouTube said: The playlist does not exist.

    The last line is misleading and is the one you will read first. The
    playlist is fine; that is simply what YouTube returns to an unauthenticated
    reader. The real failure is the first line. **This cannot be scheduled.**

  * If it reports the cookie database is locked, close that browser and retry —
    yt-dlp cannot read the cookie DB while the browser holds the file lock.
"""

import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

WL_URL = "https://www.youtube.com/playlist?list=WL"


def fetch_watch_later(browser: str) -> list[dict]:
    cmd = [
        "yt-dlp",
        "--cookies-from-browser", browser,
        "--flat-playlist",
        "--dump-json",
        WL_URL,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"yt-dlp failed (exit {result.returncode}):\n{result.stderr}", file=sys.stderr)
        print(
            "If this mentions the cookie database being locked, close that "
            "browser and try again. If it mentions 'no key found' followed by "
            "'The playlist does not exist', the cookies could not be decrypted "
            "— see this script's docstring.",
            file=sys.stderr,
        )
        sys.exit(1)

    entries = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            entries.append(json.loads(line))
    return entries


def format_duration(duration) -> str:
    if not isinstance(duration, (int, float)):
        return "?"
    minutes, seconds = divmod(int(duration), 60)
    return f"{minutes}:{seconds:02d}"


def render_note(entries: list[dict], today: str) -> str:
    lines = [
        "---",
        f"date: {today}",
        "source: youtube-watch-later",
        f"count: {len(entries)}",
        "---",
        "",
        f"# YouTube Watch Later — {today}",
        "",
        f"{len(entries)} videos, in Watch Later order.",
        "",
    ]
    for e in entries:
        title = (e.get("title") or "(no title)").replace("[", "(").replace("]", ")")
        channel = e.get("channel") or e.get("uploader") or "(unknown channel)"
        video_id = e.get("id", "")
        url = f"https://www.youtube.com/watch?v={video_id}" if video_id else e.get("url", "")
        duration = format_duration(e.get("duration"))
        lines.append(f"- [{title}]({url}) — {channel}, {duration}")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch your YouTube Watch Later playlist and write it as a markdown note.",
    )
    parser.add_argument(
        "--browser",
        default="firefox",
        help="Browser yt-dlp reads cookies from (firefox, chrome, brave, "
        "vivaldi, edge, safari, ...). Must be signed into YouTube. Default: "
        "firefox — yt-dlp's convention, not necessarily the right one for you.",
    )
    parser.add_argument(
        "--out-dir",
        default=".",
        help="Directory to write watch-later-<date>.md into. "
        "Default: current directory.",
    )
    args = parser.parse_args()

    today = date.today().isoformat()
    entries = fetch_watch_later(args.browser)
    note = render_note(entries, today)

    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"watch-later-{today}.md"
    out_path.write_text(note)

    print(f"{len(entries)} videos written to {out_path}")


if __name__ == "__main__":
    main()
