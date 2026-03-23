#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from release_support import ReleaseError, parse_version_file, upsert_appcast_item


def main() -> int:
    parser = argparse.ArgumentParser(description="Insert or replace the current release item in appcast.xml.")
    parser.add_argument("--appcast", type=Path, default=Path("appcast.xml"), help="Path to appcast.xml")
    parser.add_argument(
        "--version-file",
        type=Path,
        default=Path("Config/Version.xcconfig"),
        help="Path to the canonical version xcconfig file.",
    )
    parser.add_argument("--pub-date", required=True, help="RFC 2822 publication date")
    parser.add_argument("--download-url", required=True, help="Public update archive URL")
    parser.add_argument("--length", required=True, type=int, help="Archive length in bytes")
    parser.add_argument("--ed-signature", required=True, help="Sparkle EdDSA signature")
    args = parser.parse_args()

    try:
        version = parse_version_file(args.version_file)
        upsert_appcast_item(
            appcast_path=args.appcast,
            version=version,
            pub_date=args.pub_date,
            download_url=args.download_url,
            archive_length=args.length,
            ed_signature=args.ed_signature,
        )
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Updated {args.appcast} with {version.marketing_version} (build {version.build_number})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
