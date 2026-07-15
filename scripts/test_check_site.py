#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check-site.py")
SPEC = importlib.util.spec_from_file_location("check_site", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load generated-site checker")
check_site = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_site)


class GeneratedSiteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.write(".nojekyll", "")
        self.write("CNAME", "site.example\n")
        self.write("archive/index.html", "<html><body>archive</body></html>\n")
        self.write("feed.xml", "<feed></feed>\n")
        self.write("index.html", "<html><body id='home'>home</body></html>\n")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write(self, name: str, content: str) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def errors(self) -> list[str]:
        return check_site.check(self.root)

    def test_minimal_site_passes(self) -> None:
        self.assertEqual(self.errors(), [])

    def test_missing_local_target_fails(self) -> None:
        self.write("index.html", "<a href='/missing/'>missing</a>\n")
        self.assertTrue(any("missing href target" in item for item in self.errors()))

    def test_missing_fragment_fails(self) -> None:
        self.write("index.html", "<a href='/archive/#missing'>archive</a>\n")
        self.assertTrue(any("missing fragment target" in item for item in self.errors()))

    def test_path_traversal_fails(self) -> None:
        self.write("index.html", "<a href='../../outside'>outside</a>\n")
        self.assertTrue(any("escapes site root" in item for item in self.errors()))

    def test_duplicate_id_fails(self) -> None:
        self.write("index.html", "<i id='same'></i><b id='same'></b>\n")
        self.assertTrue(any("duplicate id #same" in item for item in self.errors()))

    def test_unsafe_scheme_fails(self) -> None:
        self.write("index.html", "<a href='javascript:alert(1)'>bad</a>\n")
        self.assertTrue(any("unsafe URL scheme" in item for item in self.errors()))

    def test_external_links_are_not_fetched(self) -> None:
        self.write(
            "index.html",
            "<a href='https://example.test/a'>web</a>"
            "<a href='mailto:person@example.test'>mail</a>\n",
        )
        self.assertEqual(self.errors(), [])

    def test_same_site_feed_target_is_checked(self) -> None:
        self.write(
            "feed.xml",
            "<feed><link href='https://site.example/missing/' /></feed>\n",
        )
        self.assertTrue(any("missing href target" in item for item in self.errors()))

    def test_css_asset_target_is_checked(self) -> None:
        self.write("static/site.css", "body { background: url('/missing.png'); }\n")
        self.assertTrue(any("missing CSS url target" in item for item in self.errors()))


if __name__ == "__main__":
    unittest.main()
