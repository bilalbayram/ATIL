#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from release_support import ReleaseError, generate_release_notes


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate ATIL release notes from git history.")
    parser.add_argument("--marketing-version", required=True, help="Release marketing version, e.g. 1.0.4")
    parser.add_argument(
        "--current-ref",
        default="HEAD",
        help="Git ref that represents the release commit. Defaults to HEAD.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path("."),
        help="Repository root containing the git metadata.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional output file path. If omitted, notes are written to stdout.",
    )
    args = parser.parse_args()

    try:
        notes = generate_release_notes(
            marketing_version=args.marketing_version,
            repo_root=args.repo_root,
            current_ref=args.current_ref,
        )
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.output is None:
        sys.stdout.write(notes)
    else:
        args.output.write_text(notes, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
