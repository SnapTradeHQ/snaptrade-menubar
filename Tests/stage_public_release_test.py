import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "Scripts/stage_public_release.py"
spec = importlib.util.spec_from_file_location("stage_public_release", SCRIPT)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class StagePublicReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.site = root / "site"
        self.tap = root / "tap"
        self.artifacts = root / "artifacts"
        self.info = root / "Info.plist"
        (self.site / ".openai").mkdir(parents=True)
        (self.site / ".openai/hosting.json").write_text(
            '{"project_id":"appgprj_6aa3aa61d23081918be55584be46354c"}'
        )
        (self.site / "dist/updates").mkdir(parents=True)
        (self.tap / "Casks").mkdir(parents=True)
        (self.artifacts / "updates").mkdir(parents=True)
        (self.site / "dist/index.html").write_text(
            '<a class="button" href="/updates/SnapTradeMenuBar-0.1.5-6.dmg" download>Download for Mac</a>'
            '<a class="button" href="/updates/SnapTradeMenuBar-0.1.5-6.dmg" download>Download for Mac</a>'
            '<p class="checksum"><a href="/updates/SnapTradeMenuBar-0.1.5-6.dmg.sha256">'
            'SHA-256 checksum</a> · 0.1.5 · 3.0 MB</p>'
            '<code>brew install --cask snaptradehq/tap/menubar</code>'
        )
        (self.tap / "Casks/menubar.rb").write_text(
            'cask "menubar" do\n'
            '  version "0.1.5-6"\n'
            f'  sha256 "{"0" * 64}"\n'
            '  url "https://menubar.snaptra.de/updates/SnapTradeMenuBar-#{version}.dmg"\n'
            'end\n'
        )
        with self.info.open("wb") as handle:
            plistlib.dump({"CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "7"}, handle)
        dmg = b"signed installer bytes"
        (self.artifacts / "SnapTradeMenuBar-0.2.0-7.dmg").write_bytes(dmg)
        (self.artifacts / "updates/SnapTradeMenuBar-0.2.0-7.dmg").write_bytes(dmg)
        (self.artifacts / "updates/SnapTradeMenuBar-0.2.0-7.md").write_text("Release notes")
        (self.artifacts / "updates/appcast.xml").write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
            '<sparkle:version>7</sparkle:version>'
            '<sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>'
            '<sparkle:releaseNotesLink>https://menubar.snaptra.de/updates/SnapTradeMenuBar-0.2.0-7.md</sparkle:releaseNotesLink>'
            f'<enclosure url="https://menubar.snaptra.de/updates/SnapTradeMenuBar-0.2.0-7.dmg" length="{len(dmg)}" sparkle:edSignature="signed" />'
            '</item></channel></rss>'
        )

    def test_stages_new_release_and_preserves_other_site_content(self):
        (self.site / "dist/updates/older-note.md").write_text("Keep this")
        version, checksum = release.stage(self.site, self.tap, self.artifacts, self.info)
        self.assertEqual(version, "0.2.0-7")
        self.assertEqual(len(checksum), 64)
        html = (self.site / "dist/index.html").read_text()
        self.assertEqual(html.count("/updates/SnapTradeMenuBar-0.2.0-7.dmg\" download"), 2)
        self.assertIn("0.2.0 · 0.0 MB", html)
        self.assertIn("brew install --cask snaptradehq/tap/menubar", html)
        self.assertIn('version "0.2.0-7"', (self.tap / "Casks/menubar.rb").read_text())
        self.assertIn(checksum, (self.tap / "Casks/menubar.rb").read_text())
        self.assertEqual((self.site / "dist/updates/older-note.md").read_text(), "Keep this")
        self.assertEqual((self.site / "dist/updates/SnapTradeMenuBar-0.2.0-7.dmg").read_bytes(), b"signed installer bytes")
        self.assertEqual((self.site / "dist/updates/SnapTradeMenuBar-0.2.0-7.dmg.sha256").read_text(),
                         f"{checksum}  SnapTradeMenuBar-0.2.0-7.dmg\n")

    def test_rejects_feed_for_another_build_before_editing(self):
        appcast = self.artifacts / "updates/appcast.xml"
        appcast.write_text(appcast.read_text().replace("<sparkle:version>7", "<sparkle:version>8"))
        original = (self.site / "dist/index.html").read_text()
        with self.assertRaisesRegex(ValueError, "different build"):
            release.stage(self.site, self.tap, self.artifacts, self.info)
        self.assertEqual((self.site / "dist/index.html").read_text(), original)

    def test_rejects_replacing_published_release_bytes(self):
        (self.site / "dist/updates/SnapTradeMenuBar-0.2.0-7.dmg").write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "Refusing to replace"):
            release.stage(self.site, self.tap, self.artifacts, self.info)

    def test_rewrites_historical_feed_urls_to_current_domain(self):
        historical = (
            '<item><sparkle:version>6</sparkle:version>'
            '<enclosure url="https://menubar.snaptrade.com/updates/SnapTradeMenuBar-0.1.5-6.dmg" />'
            '</item>'
        )
        appcast = self.artifacts / "updates/appcast.xml"
        appcast.write_text(appcast.read_text().replace("</channel>", historical + "</channel>"))
        (self.artifacts / "updates/SnapTradeMenuBar-0.1.5-6.dmg").write_bytes(b"older")
        release.stage(self.site, self.tap, self.artifacts, self.info)
        staged = (self.site / "dist/updates/appcast.xml").read_text()
        self.assertNotIn("menubar.snaptrade.com", staged)
        self.assertIn("menubar.snaptra.de/updates/SnapTradeMenuBar-0.1.5-6.dmg", staged)


if __name__ == "__main__":
    unittest.main()
