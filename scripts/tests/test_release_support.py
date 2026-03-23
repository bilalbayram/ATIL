from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path
import textwrap
import unittest
import xml.etree.ElementTree as ET

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from release_support import (  # noqa: E402
    ReleaseError,
    ReleaseVersion,
    generate_release_notes,
    parse_version_file,
    prepare_release,
    sparkle_tag,
    upsert_appcast_item,
)


APPCAST_FIXTURE = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>ATIL</title>
        <item>
            <title>Version 1.0.2</title>
            <sparkle:version>1.0.2</sparkle:version>
            <sparkle:shortVersionString>1.0.2</sparkle:shortVersionString>
            <pubDate>Tue, 17 Mar 2026 13:50:51 +0000</pubDate>
            <enclosure url="https://example.com/ATIL-1.0.2.zip" sparkle:edSignature="sig-102" length="123" type="application/octet-stream" />
        </item>
        <item>
            <title>Version 1.0.3</title>
            <sparkle:version>1.0.3</sparkle:version>
            <sparkle:shortVersionString>1.0.3</sparkle:shortVersionString>
            <pubDate>Tue, 17 Mar 2026 14:00:23 +0000</pubDate>
            <enclosure url="https://example.com/ATIL-1.0.3.zip" sparkle:edSignature="sig-103" length="456" type="application/octet-stream" />
        </item>
    </channel>
</rss>
"""


class VersionFileTests(unittest.TestCase):
    def test_parse_version_file_reads_semver_and_integer_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            version_file = Path(temporary_directory) / "Version.xcconfig"
            version_file.write_text(
                textwrap.dedent(
                    """\
                    // Version metadata
                    MARKETING_VERSION = 1.0.4
                    CURRENT_PROJECT_VERSION = 4
                    """
                ),
                encoding="utf-8",
            )

            version = parse_version_file(version_file)

        self.assertEqual(version, ReleaseVersion("1.0.4", 4))

    def test_prepare_release_bumps_build_and_updates_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            version_file = Path(temporary_directory) / "Version.xcconfig"
            version_file.write_text(
                "MARKETING_VERSION = 1.0.4\nCURRENT_PROJECT_VERSION = 4\n",
                encoding="utf-8",
            )

            version = prepare_release(version_file, "1.0.5")
            written = parse_version_file(version_file)

        self.assertEqual(version, ReleaseVersion("1.0.5", 5))
        self.assertEqual(written, ReleaseVersion("1.0.5", 5))

    def test_prepare_release_rejects_non_monotonic_versions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            version_file = Path(temporary_directory) / "Version.xcconfig"
            version_file.write_text(
                "MARKETING_VERSION = 1.0.4\nCURRENT_PROJECT_VERSION = 4\n",
                encoding="utf-8",
            )

            with self.assertRaises(ReleaseError):
                prepare_release(version_file, "1.0.4")

    def test_parse_version_file_rejects_non_integer_builds(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            version_file = Path(temporary_directory) / "Version.xcconfig"
            version_file.write_text(
                "MARKETING_VERSION = 1.0.4\nCURRENT_PROJECT_VERSION = 1.0.4\n",
                encoding="utf-8",
            )

            with self.assertRaises(ReleaseError):
                parse_version_file(version_file)


class AppcastTests(unittest.TestCase):
    def test_upsert_prepends_new_item_and_uses_build_number(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            appcast_path = Path(temporary_directory) / "appcast.xml"
            appcast_path.write_text(APPCAST_FIXTURE, encoding="utf-8")

            upsert_appcast_item(
                appcast_path=appcast_path,
                version=ReleaseVersion("1.0.4", 4),
                pub_date="Tue, 24 Mar 2026 10:00:00 +0000",
                download_url="https://example.com/ATIL-1.0.4.zip",
                archive_length=789,
                ed_signature="sig-104",
            )

            tree = ET.parse(appcast_path)
            items = tree.getroot().find("channel").findall("item")

        self.assertEqual(items[0].findtext(sparkle_tag("shortVersionString")), "1.0.4")
        self.assertEqual(items[0].findtext(sparkle_tag("version")), "4")
        self.assertEqual(items[0].find("enclosure").get("length"), "789")
        self.assertEqual(len(items), 3)

    def test_upsert_is_idempotent_for_same_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            appcast_path = Path(temporary_directory) / "appcast.xml"
            appcast_path.write_text(APPCAST_FIXTURE, encoding="utf-8")

            version = ReleaseVersion("1.0.4", 4)
            upsert_appcast_item(
                appcast_path=appcast_path,
                version=version,
                pub_date="Tue, 24 Mar 2026 10:00:00 +0000",
                download_url="https://example.com/ATIL-1.0.4.zip",
                archive_length=789,
                ed_signature="sig-104",
            )
            upsert_appcast_item(
                appcast_path=appcast_path,
                version=version,
                pub_date="Tue, 24 Mar 2026 11:00:00 +0000",
                download_url="https://example.com/ATIL-1.0.4.zip",
                archive_length=790,
                ed_signature="sig-104b",
            )

            tree = ET.parse(appcast_path)
            items = tree.getroot().find("channel").findall("item")

        matching_items = [
            item
            for item in items
            if item.findtext(sparkle_tag("shortVersionString")) == "1.0.4"
        ]
        self.assertEqual(len(matching_items), 1)
        self.assertEqual(matching_items[0].find("enclosure").get("length"), "790")


class ReleaseNotesTests(unittest.TestCase):
    def test_generate_release_notes_uses_override_and_filters_housekeeping(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repo_root = Path(temporary_directory)
            self.initialise_git_repo(repo_root)

            self.commit(repo_root, "Initial commit")
            self.run_git(repo_root, "tag", "v1.0.3")
            override_anchor = self.commit(repo_root, "Update appcast for v1.0.3")
            self.commit(repo_root, "Add default apps settings")
            self.commit(repo_root, "Release 1.0.4 (build 4)")

            notes = generate_release_notes(
                marketing_version="1.0.4",
                repo_root=repo_root,
                anchors={"1.0.4": override_anchor},
            )

        self.assertIn("- Add default apps settings", notes)
        self.assertNotIn("Update appcast for v1.0.3", notes)
        self.assertNotIn("Release 1.0.4 (build 4)", notes)

    def test_generate_release_notes_uses_previous_tag_after_first_fixed_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repo_root = Path(temporary_directory)
            self.initialise_git_repo(repo_root)

            self.commit(repo_root, "Initial commit")
            self.commit(repo_root, "Release 1.0.4 (build 4)")
            self.run_git(repo_root, "tag", "v1.0.4")
            self.commit(repo_root, "Improve Sparkle validation")
            self.run_git(repo_root, "tag", "v1.0.5")

            notes = generate_release_notes(
                marketing_version="1.0.5",
                repo_root=repo_root,
                current_ref="v1.0.5",
                anchors={},
            )

        self.assertIn("- Improve Sparkle validation", notes)

    def initialise_git_repo(self, repo_root: Path) -> None:
        self.run_git(repo_root, "init")
        self.run_git(repo_root, "config", "user.name", "ATIL Tests")
        self.run_git(repo_root, "config", "user.email", "atil-tests@example.com")

    def commit(self, repo_root: Path, message: str) -> str:
        file_path = repo_root / "history.txt"
        existing = file_path.read_text(encoding="utf-8") if file_path.exists() else ""
        file_path.write_text(existing + message + "\n", encoding="utf-8")
        self.run_git(repo_root, "add", "history.txt")
        self.run_git(repo_root, "commit", "-m", message)
        return self.run_git(repo_root, "rev-parse", "HEAD")

    def run_git(self, repo_root: Path, *args: str) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=repo_root,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()


if __name__ == "__main__":
    unittest.main()
