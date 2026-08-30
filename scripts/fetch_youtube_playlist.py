#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = ["yt-dlp"]
# ///
"""
Fetch a YouTube playlist and write it as a markdown note. No account needed.

Give it a **public or unlisted** playlist and it reads the list anonymously —
no cookies, no login, no browser involved at all. That is the entire point of
this script, and it is worth spelling out because the obvious alternative is a
trap:

  * The **Watch Later** playlist cannot be read this way, or any other way.
    Google deprecated `watchLater` in the Data API in August 2016; it now
    returns the placeholder id `WL` and nothing else. The only remaining route
    is exporting your browser cookies, and yt-dlp's own documentation warns
    that "by using your account with yt-dlp, you run the risk of it being
    banned (temporarily or permanently)". On Windows it does not even work any
    more: Chrome 127+ binds the cookie key to the browser binary (App-Bound
    Encryption), so no external process can decrypt it.

  * A **normal playlist you create yourself** has none of those problems. Save
    videos to one instead of to Watch Later and every request this script makes
    is anonymous — there is no account attached to it, so there is nothing to
    ban and no credential to leak.

**Unlisted, not Private.** Unlisted means "not in search, readable by anyone
with the id", which is what makes the anonymous read work. A Private playlist
is readable only by you, signed in, and this script will fail on it. The trade
is real and worth stating: anyone who learns the playlist id can see what is in
it. The id is long and unguessable, but it is not a secret.

Usage:

    uv run ~/justscripts/scripts/fetch_youtube_playlist.py --playlist PL123...
    uv run ~/justscripts/scripts/fetch_youtube_playlist.py --playlist 'https://www.youtube.com/playlist?list=PL123...'
    just yt-playlist PL123... ~/some/folder

Writes `youtube-<slug>-<YYYY-MM-DD>.md` into the output directory (default: the
current directory): front-matter with the date, playlist id, playlist title and
video count, then one `- [title](url) — channel, m:ss` line per video, in
playlist order.

Read-only. Nothing here writes to YouTube.
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path


def playlist_url(playlist: str) -> str:
    """Accept a full URL or a bare playlist id."""
    if playlist.startswith(("http://", "https://")):
        return playlist
    return f"https://www.youtube.com/playlist?list={playlist}"


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "playlist"


def fetch_playlist(playlist: str, limit: int | None) -> list[dict]:
    cmd = ["yt-dlp", "--flat-playlist", "--dump-json"]
    if limit:
        cmd += ["--playlist-end", str(limit)]
    cmd.append(playlist_url(playlist))

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        stderr = result.stderr
        print(f"yt-dlp failed (exit {result.returncode}):\n{stderr}", file=sys.stderr)
        if "does not exist" in stderr or "private" in stderr.lower():
            print(
                "\nA playlist that is PRIVATE cannot be read without signing in. "
                "Set it to UNLISTED instead — unlisted playlists are readable by "
                "anyone holding the id, which is what lets this run with no "
                "account. Note that 'WL' (Watch Later) can never be read this "
                "way; see this script's docstring.",
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


def render_note(entries: list[dict], playlist_id: str, title: str, today: str) -> str:
    lines = [
        "---",
        f"date: {today}",
        "source: youtube-playlist",
        f"playlist_id: {playlist_id}",
        f"playlist_title: {title}",
        f"count: {len(entries)}",
        "---",
        "",
        f"# {title} — {today}",
        "",
        f"{len(entries)} videos, in playlist order.",
        "",
    ]
    for e in entries:
        vid_title = (e.get("title") or "(no title)").replace("[", "(").replace("]", ")")
        channel = e.get("channel") or e.get("uploader") or "(unknown channel)"
        video_id = e.get("id", "")
        url = f"https://www.youtube.com/watch?v={video_id}" if video_id else e.get("url", "")
        duration = format_duration(e.get("duration"))
        lines.append(f"- [{vid_title}]({url}) — {channel}, {duration}")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch a public or unlisted YouTube playlist and write it as a markdown note.",
    )
    parser.add_argument(
        "--playlist",
        required=True,
        help="Playlist id (PL..., UU...) or a full playlist URL. Must be public "
        "or unlisted — a private playlist needs a login and will fail.",
    )
    parser.add_argument(
        "--out-dir",
        default=".",
        help="Directory to write the note into. Default: current directory.",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Override the playlist name used in the filename and heading. "
        "Default: the playlist's own title as YouTube reports it.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only read the first N videos. Useful for a quick check.",
    )
    args = parser.parse_args()

    today = date.today().isoformat()
    entries = fetch_playlist(args.playlist, args.limit)

    playlist_id = next((e.get("playlist_id") for e in entries if e.get("playlist_id")), args.playlist)
    title = args.name or next(
        (e.get("playlist_title") for e in entries if e.get("playlist_title")), "YouTube playlist"
    )

    note = render_note(entries, playlist_id, title, today)

    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"youtube-{slugify(title)}-{today}.md"
    out_path.write_text(note)

    print(f"{len(entries)} videos written to {out_path}")


if __name__ == "__main__":
    main()
