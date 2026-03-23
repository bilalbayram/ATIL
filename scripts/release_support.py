#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NAMESPACE = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE_NAMESPACE)
ET.register_namespace("dc", DC_NAMESPACE)

VERSION_LINE_PATTERN = re.compile(r"^([A-Z0-9_]+)\s*=\s*(.+?)\s*$")
MARKETING_VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
HOUSEKEEPING_SUBJECT_PATTERNS = (
    re.compile(r"^Release .+ \(build \d+\)$"),
    re.compile(r"^Update appcast for v.+$"),
)
DEFAULT_RELEASE_ANCHORS = {
    "1.0.4": "c75a503",
}


class ReleaseError(RuntimeError):
    """Raised when release metadata is invalid."""


@dataclass(frozen=True)
class ReleaseVersion:
    marketing_version: str
    build_number: int

    @property
    def tag(self) -> str:
        return f"v{self.marketing_version}"

    @property
    def commit_message(self) -> str:
        return f"Release {self.marketing_version} (build {self.build_number})"


def parse_version_file(path: Path) -> ReleaseVersion:
    values: dict[str, str] = {}

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue

        match = VERSION_LINE_PATTERN.match(line)
        if match is None:
            raise ReleaseError(f"Invalid version config line: {raw_line}")

        key, value = match.groups()
        values[key] = value

    marketing_version = values.get("MARKETING_VERSION")
    build_number = values.get("CURRENT_PROJECT_VERSION")

    if marketing_version is None or build_number is None:
        raise ReleaseError("Version file must define MARKETING_VERSION and CURRENT_PROJECT_VERSION")
    if MARKETING_VERSION_PATTERN.fullmatch(marketing_version) is None:
        raise ReleaseError(f"MARKETING_VERSION must be semver x.y.z, got {marketing_version}")
    if not build_number.isdigit():
        raise ReleaseError(f"CURRENT_PROJECT_VERSION must be an integer, got {build_number}")

    return ReleaseVersion(marketing_version=marketing_version, build_number=int(build_number))


def write_version_file(path: Path, version: ReleaseVersion) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(
            [
                "// Canonical version metadata for ATIL releases.",
                "// MARKETING_VERSION is user-facing.",
                "// CURRENT_PROJECT_VERSION is the monotonic integer build number Sparkle compares.",
                f"MARKETING_VERSION = {version.marketing_version}",
                f"CURRENT_PROJECT_VERSION = {version.build_number}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def semver_key(version: str) -> tuple[int, int, int]:
    if MARKETING_VERSION_PATTERN.fullmatch(version) is None:
        raise ReleaseError(f"Invalid semantic version: {version}")
    return tuple(int(part) for part in version.split("."))


def prepare_release(version_file: Path, requested_marketing_version: str) -> ReleaseVersion:
    current_version = parse_version_file(version_file)

    if semver_key(requested_marketing_version) <= semver_key(current_version.marketing_version):
        raise ReleaseError(
            f"Requested version {requested_marketing_version} must be newer than {current_version.marketing_version}"
        )

    next_version = ReleaseVersion(
        marketing_version=requested_marketing_version,
        build_number=current_version.build_number + 1,
    )
    write_version_file(version_file, next_version)
    return next_version


def sparkle_tag(name: str) -> str:
    return f"{{{SPARKLE_NAMESPACE}}}{name}"


def build_appcast_item(
    version: ReleaseVersion,
    pub_date: str,
    download_url: str,
    archive_length: int,
    ed_signature: str,
) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version.marketing_version}"
    ET.SubElement(item, sparkle_tag("version")).text = str(version.build_number)
    ET.SubElement(item, sparkle_tag("shortVersionString")).text = version.marketing_version
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": download_url,
            sparkle_tag("edSignature"): ed_signature,
            "length": str(archive_length),
            "type": "application/octet-stream",
        },
    )
    return item


def upsert_appcast_item(
    appcast_path: Path,
    version: ReleaseVersion,
    pub_date: str,
    download_url: str,
    archive_length: int,
    ed_signature: str,
) -> None:
    tree = ET.parse(appcast_path)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        raise ReleaseError("appcast.xml is missing its channel element")

    for existing_item in list(channel.findall("item")):
        short_version = existing_item.findtext(sparkle_tag("shortVersionString"))
        if short_version == version.marketing_version:
            channel.remove(existing_item)

    new_item = build_appcast_item(
        version=version,
        pub_date=pub_date,
        download_url=download_url,
        archive_length=archive_length,
        ed_signature=ed_signature,
    )

    first_item_index = next(
        (index for index, child in enumerate(list(channel)) if child.tag == "item"),
        len(channel),
    )
    channel.insert(first_item_index, new_item)

    ET.indent(tree, space="    ")
    tree.write(appcast_path, encoding="utf-8", xml_declaration=True)


def find_appcast_item(appcast_path: Path, marketing_version: str) -> ET.Element:
    tree = ET.parse(appcast_path)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ReleaseError("appcast.xml is missing its channel element")

    for item in channel.findall("item"):
        if item.findtext(sparkle_tag("shortVersionString")) == marketing_version:
            return item

    raise ReleaseError(f"No appcast item found for version {marketing_version}")


def load_bundle_versions(app_path: Path) -> tuple[str, str]:
    info_plist_path = app_path / "Contents" / "Info.plist"
    if not info_plist_path.exists():
        raise ReleaseError(f"Missing Info.plist at {info_plist_path}")

    with info_plist_path.open("rb") as handle:
        plist = plistlib.load(handle)

    marketing_version = plist.get("CFBundleShortVersionString")
    build_number = plist.get("CFBundleVersion")
    if not isinstance(marketing_version, str) or not isinstance(build_number, str):
        raise ReleaseError("Built app is missing CFBundleShortVersionString or CFBundleVersion")

    return marketing_version, build_number


def validate_release_metadata(
    version_file: Path,
    app_path: Path,
    tag: str | None = None,
    appcast_path: Path | None = None,
    download_url: str | None = None,
    archive_length: int | None = None,
    ed_signature: str | None = None,
) -> None:
    version = parse_version_file(version_file)
    errors: list[str] = []

    if tag is not None and tag != version.tag:
        errors.append(f"Tag {tag} does not match version file tag {version.tag}")

    app_marketing_version, app_build_number = load_bundle_versions(app_path)
    if app_marketing_version != version.marketing_version:
        errors.append(
            f"Built app marketing version {app_marketing_version} does not match {version.marketing_version}"
        )
    if app_build_number != str(version.build_number):
        errors.append(f"Built app build number {app_build_number} does not match {version.build_number}")

    if appcast_path is not None:
        item = find_appcast_item(appcast_path, version.marketing_version)
        appcast_build_number = item.findtext(sparkle_tag("version"))
        if appcast_build_number != str(version.build_number):
            errors.append(
                f"Appcast sparkle:version {appcast_build_number} does not match build {version.build_number}"
            )

        enclosure = item.find("enclosure")
        if enclosure is None:
            errors.append("Appcast item is missing enclosure")
        else:
            if download_url is not None and enclosure.get("url") != download_url:
                errors.append(f"Appcast enclosure url {enclosure.get('url')} does not match {download_url}")
            if archive_length is not None and enclosure.get("length") != str(archive_length):
                errors.append(
                    f"Appcast enclosure length {enclosure.get('length')} does not match {archive_length}"
                )
            signature_key = sparkle_tag("edSignature")
            if ed_signature is not None and enclosure.get(signature_key) != ed_signature:
                errors.append("Appcast enclosure EdDSA signature does not match expected signature")

    if errors:
        raise ReleaseError("\n".join(errors))


def previous_release_ref(
    marketing_version: str,
    repo_root: Path,
    current_tag: str | None = None,
    anchors: dict[str, str] | None = None,
) -> str:
    active_anchors = anchors if anchors is not None else DEFAULT_RELEASE_ANCHORS
    if marketing_version in active_anchors:
        return active_anchors[marketing_version]

    tag_name = current_tag or f"v{marketing_version}"
    tags_output = git_output(repo_root, "tag", "--sort=version:refname")
    tags = [tag for tag in tags_output.splitlines() if tag]
    if tag_name not in tags:
        raise ReleaseError(f"Could not find current tag {tag_name}")

    tag_index = tags.index(tag_name)
    if tag_index == 0:
        raise ReleaseError(f"No previous tag exists before {tag_name}")

    return tags[tag_index - 1]


def generate_release_notes(
    marketing_version: str,
    repo_root: Path,
    current_ref: str = "HEAD",
    anchors: dict[str, str] | None = None,
) -> str:
    start_ref = previous_release_ref(marketing_version, repo_root, anchors=anchors)
    subjects_output = git_output(repo_root, "log", "--reverse", "--format=%s", f"{start_ref}..{current_ref}")
    subjects = [subject for subject in subjects_output.splitlines() if subject]
    filtered_subjects = [
        subject
        for subject in subjects
        if not any(pattern.match(subject) for pattern in HOUSEKEEPING_SUBJECT_PATTERNS)
    ]

    lines = ["## What's Changed", ""]
    if filtered_subjects:
        lines.extend(f"- {subject}" for subject in filtered_subjects)
    else:
        lines.append("- No user-facing changes recorded.")

    return "\n".join(lines) + "\n"


def git_output(repo_root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()
