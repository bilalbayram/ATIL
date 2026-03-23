#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from release_support import ReleaseError, prepare_release


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare the next ATIL release version.")
    parser.add_argument("marketing_version", help="New user-facing version, e.g. 1.0.5")
    parser.add_argument(
        "--version-file",
        type=Path,
        default=Path("Config/Version.xcconfig"),
        help="Path to the canonical version xcconfig file.",
    )
    args = parser.parse_args()

    try:
        version = prepare_release(args.version_file, args.marketing_version)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Prepared {version.marketing_version} (build {version.build_number})")
    print(f"Commit message: {version.commit_message}")
    print(f"Tag: {version.tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
