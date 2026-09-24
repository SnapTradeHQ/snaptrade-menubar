#!/usr/bin/env python3
"""Stage a signed MenuBar release in the Site and Homebrew tap checkouts.

This changes local files only. Publish the Site before pushing the cask so the
cask never points at an installer that is not live yet.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parent.parent
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def require_clean_checkout(path: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(path), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    )
    require(result.returncode == 0 and not result.stdout.strip(),
            f"Checkout must be a clean Git working tree: {path}")


def replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text)
    require(count == 1, f"Expected one {label}; found {count}")
    return updated


def prepare_site_html(html: str, dmg_name: str, version: str, size: int) -> str:
    url = f'/updates/{dmg_name}'
    html, count = re.subn(
        r'href="/updates/SnapTradeMenuBar-[^"/]+\.dmg"(?= download>Download for Mac</a>)',
        lambda _: f'href="{url}"',
        html,
    )
    require(count == 2, f"Expected two direct download buttons; found {count}")
    html = replace_once(
        html,
        r'href="/updates/SnapTradeMenuBar-[^"/]+\.dmg\.sha256"',
        f'href="{url}.sha256"',
        "checksum link",
    )
    return replace_once(
        html,
        r'SHA-256 checksum</a> · [^<]+</p>',
        f'SHA-256 checksum</a> · {version} · {size / 1_000_000:.1f} MB</p>',
        "download metadata",
    )


def prepare_cask(cask: str, version: str, checksum: str) -> str:
    require('url "https://menubar.snaptra.de/updates/SnapTradeMenuBar-#{version}.dmg"' in cask,
            "Cask URL is not version-derived")
    cask = replace_once(cask, r'(?m)^  version "[^"]+"$', f'  version "{version}"', "cask version")
    return replace_once(cask, r'(?m)^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{checksum}"', "cask checksum")


def asset_names(item: ET.Element) -> set[str]:
    urls = [enclosure.get("url", "") for enclosure in item.findall("enclosure")]
    notes_url = item.findtext(f"{SPARKLE}releaseNotesLink")
    if notes_url:
        urls.append(notes_url)
    urls.extend(enclosure.get("url", "") for enclosure in item.findall(f"{SPARKLE}deltas/enclosure"))
    names = set()
    for url in urls:
        parsed = urlparse(url)
        name = Path(unquote(parsed.path)).name
        require(parsed.scheme == "https" and parsed.netloc == "menubar.snaptra.de"
                and parsed.path.startswith("/updates/") and name not in {"", ".", ".."},
                f"Appcast has an unexpected asset URL: {url}")
        names.add(name)
    return names


def validate_appcast(appcast_xml: str, version: str, build: str, dmg_name: str, size: int) -> tuple[set[str], set[str]]:
    channel = ET.fromstring(appcast_xml).find("channel")
    require(channel is not None, "Appcast has no channel")
    latest = channel.find("item")
    require(latest is not None, "Appcast has no release")
    require(latest.findtext(f"{SPARKLE}shortVersionString") == version,
            "Appcast's newest release has a different app version")
    require(latest.findtext(f"{SPARKLE}version") == build,
            "Appcast's newest release has a different build")
    enclosure = latest.find("enclosure")
    require(enclosure is not None, "Newest appcast item has no full installer")
    require(urlparse(enclosure.get("url", "")).path == f"/updates/{dmg_name}",
            "Appcast installer URL does not match this release")
    require(enclosure.get("length") == str(size), "Appcast installer size does not match the DMG")
    require(bool(enclosure.get(f"{SPARKLE}edSignature")), "Appcast installer is not Sparkle-signed")
    current_assets = asset_names(latest)
    all_assets = set().union(*(asset_names(item) for item in channel.findall("item")))
    return current_assets, all_assets


def stage(site: Path, tap: Path, artifacts: Path, info_plist: Path) -> tuple[str, str]:
    with info_plist.open("rb") as handle:
        info = plistlib.load(handle)
    version = info["CFBundleShortVersionString"]
    build = str(info["CFBundleVersion"])
    cask_version = f"{version}-{build}"
    dmg_name = f"SnapTradeMenuBar-{cask_version}.dmg"
    updates = artifacts / "updates"
    dmg = updates / dmg_name
    require(dmg.is_file(), f"Missing signed update DMG: {dmg}")
    require((artifacts / dmg_name).is_file(), "Missing packaged release DMG")
    require(dmg.read_bytes() == (artifacts / dmg_name).read_bytes(),
            "Packaged DMG differs from the signed update DMG")
    size = dmg.stat().st_size
    require(size > 0, "Release DMG is empty")
    checksum = hashlib.sha256(dmg.read_bytes()).hexdigest()
    appcast_xml = (updates / "appcast.xml").read_text()
    # Sparkle preserves URLs from historical entries when regenerating a feed.
    # Keep their paths and signatures, but serve them from the current domain.
    staged_appcast_xml = appcast_xml.replace(
        "https://menubar.snaptrade.com/updates/", "https://menubar.snaptra.de/updates/"
    )
    current_assets, all_assets = validate_appcast(staged_appcast_xml, version, build, dmg_name, size)
    site_index = site / "dist/index.html"
    site_updates = site / "dist/updates"
    cask_file = tap / "Casks/menubar.rb"
    require((site / ".openai/hosting.json").is_file(), "Not a Sites checkout")
    require(json.loads((site / ".openai/hosting.json").read_text()).get("project_id")
            == "appgprj_6aa3aa61d23081918be55584be46354c", "Wrong MenuBar Site checkout")
    require(site_index.is_file() and site_updates.is_dir(), "Site download files are missing")
    require(cask_file.is_file(), "Homebrew cask is missing")
    for name in all_assets:
        source = updates / name
        target = site_updates / name
        require(source.is_file() or target.is_file(), f"Appcast asset is missing: {name}")
        if name in current_assets:
            require(source.is_file(), f"Current release asset is missing: {name}")
    new_html = prepare_site_html(site_index.read_text(), dmg_name, version, size)
    new_cask = prepare_cask(cask_file.read_text(), cask_version, checksum)

    # Preserve historical assets already hosted by Sites. A current release's
    # filename is immutable, while the appcast is deliberately replaced.
    for name in all_assets:
        source = updates / name
        target = site_updates / name
        if name in current_assets:
            require(not target.exists() or target.read_bytes() == source.read_bytes(),
                    f"Refusing to replace existing release asset: {target}")
    sha_file = site_updates / f"{dmg_name}.sha256"
    expected_sha = f"{checksum}  {dmg_name}\n"
    require(not sha_file.exists() or sha_file.read_text() == expected_sha,
            f"Refusing to replace existing checksum: {sha_file}")

    for name in all_assets:
        source = updates / name
        target = site_updates / name
        if source.is_file() and not target.exists():
            shutil.copy2(source, target)
    (site_updates / "appcast.xml").write_text(staged_appcast_xml)
    sha_file.write_text(expected_sha)
    site_index.write_text(new_html)
    cask_file.write_text(new_cask)
    return cask_version, checksum


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, required=True, help="current Sites source checkout")
    parser.add_argument("--tap", type=Path, required=True, help="SnapTradeHQ/homebrew-tap checkout")
    parser.add_argument("--artifacts", type=Path, default=ROOT / ".build/release-artifacts")
    parser.add_argument("--info-plist", type=Path, default=ROOT / "Bundle/Info.plist")
    parser.add_argument("--require-clean", action="store_true", help="reject edits in either checkout before staging")
    args = parser.parse_args()
    try:
        if args.require_clean:
            require_clean_checkout(args.site)
            require_clean_checkout(args.tap)
        version, checksum = stage(args.site, args.tap, args.artifacts, args.info_plist)
    except (OSError, KeyError, ValueError, ET.ParseError) as error:
        print(f"Unable to stage release: {error}", file=sys.stderr)
        return 1
    print(f"Staged MenuBar {version} in Site and Homebrew tap checkouts (SHA-256 {checksum}).")
    print("Publish the Site and verify its live DMG before pushing the cask.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
