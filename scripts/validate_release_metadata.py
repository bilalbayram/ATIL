#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from release_support import ReleaseError, validate_release_metadata


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate built app metadata against release metadata.")
    parser.add_argument("--app-path", type=Path, required=True, help="Path to the built ATIL.app bundle")
    parser.add_argument(
        "--version-file",
        type=Path,
        default=Path("Config/Version.xcconfig"),
        help="Path to the canonical version xcconfig file.",
    )
    parser.add_argument("--tag", help="Optional expected git tag, e.g. v1.0.4")
    parser.add_argument("--appcast", type=Path, help="Optional appcast.xml path to validate")
    parser.add_argument("--download-url", help="Expected enclosure URL when validating appcast")
    parser.add_argument("--length", type=int, help="Expected enclosure length when validating appcast")
    parser.add_argument("--ed-signature", help="Expected Sparkle EdDSA signature when validating appcast")
    args = parser.parse_args()

    try:
        validate_release_metadata(
            version_file=args.version_file,
            app_path=args.app_path,
            tag=args.tag,
            appcast_path=args.appcast,
            download_url=args.download_url,
            archive_length=args.length,
            ed_signature=args.ed_signature,
        )
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print("Release metadata is valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
