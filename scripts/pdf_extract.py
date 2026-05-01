#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pymupdf4llm",
# ]
# ///
"""
Tier 1 PDF extraction: convert a PDF to a markdown sidecar with headings preserved.

Reads <pdf-path> via pymupdf4llm and writes <pdf-path-without-extension>_text.md
next to it. Skips if the sidecar is already newer than the PDF (mtime cache).

Usage:
  pdf_extract.py <pdf-path> [--force] [--dry-run]
"""

import argparse
import sys
from pathlib import Path

import pymupdf4llm


def target_path(pdf: Path) -> Path:
    return pdf.with_name(pdf.stem + "_text.md")


def is_cache_fresh(pdf: Path, target: Path) -> bool:
    return target.exists() and target.stat().st_mtime >= pdf.stat().st_mtime


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract a PDF to <name>_text.md via pymupdf4llm (Tier 1).",
    )
    parser.add_argument("pdf", type=Path, help="Path to the source PDF")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-extract even if the sidecar is newer than the PDF",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the target path without writing anything",
    )
    args = parser.parse_args()

    pdf: Path = args.pdf
    if not pdf.is_file():
        print(f"error: not a file: {pdf}", file=sys.stderr)
        return 1
    if pdf.suffix.lower() != ".pdf":
        print(f"error: not a .pdf file: {pdf}", file=sys.stderr)
        return 1

    target = target_path(pdf)

    if args.dry_run:
        print(f"would write: {target}")
        return 0

    if not args.force and is_cache_fresh(pdf, target):
        print(f"skip (cached): {target}")
        return 0

    markdown = pymupdf4llm.to_markdown(str(pdf))
    target.write_text(markdown, encoding="utf-8")
    print(f"wrote: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
