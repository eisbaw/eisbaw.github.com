#!/usr/bin/env python3
"""Validate the generated static site without making network requests."""

from __future__ import annotations

import argparse
import sys
import urllib.parse
from html.parser import HTMLParser
from pathlib import Path


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.duplicate_ids: set[str] = set()
        self.references: list[tuple[str, str]] = []

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        for name, value in attrs:
            if value is None:
                continue
            if name == "id":
                if value in self.ids:
                    self.duplicate_ids.add(value)
                self.ids.add(value)
            elif name in {"href", "src"}:
                self.references.append((name, value))

    handle_startendtag = handle_starttag


def display(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def local_target(root: Path, source: Path, reference: str) -> Path | None:
    split = urllib.parse.urlsplit(reference)
    if split.scheme:
        if split.scheme not in {"http", "https", "mailto"}:
            raise ValueError(f"unsafe URL scheme {split.scheme}")
        return None
    if split.netloc:
        return None

    decoded = urllib.parse.unquote(split.path)
    if not decoded:
        target = source
    elif decoded.startswith("/"):
        target = root / decoded.lstrip("/")
    else:
        target = source.parent / decoded

    target = target.resolve()
    target.relative_to(root)
    if target.is_dir() or decoded.endswith("/"):
        target /= "index.html"
    return target


def check(root: Path) -> list[str]:
    errors: list[str] = []
    required = (".nojekyll", "CNAME", "archive/index.html", "index.html")
    for name in required:
        if not (root / name).is_file():
            errors.append(f"{name}: required generated file is missing")

    pages: dict[Path, Page] = {}
    for path in sorted(root.rglob("*.html")):
        parser = Page()
        try:
            parser.feed(path.read_text(encoding="utf-8"))
            parser.close()
        except Exception as error:
            errors.append(f"{display(root, path)}: HTML parse error: {error}")
            continue
        resolved = path.resolve()
        pages[resolved] = parser
        for item in sorted(parser.duplicate_ids):
            errors.append(f"{display(root, path)}: duplicate id #{item}")

    for source, page in pages.items():
        for attribute, reference in page.references:
            try:
                target = local_target(root, source, reference)
            except ValueError as error:
                errors.append(f"{display(root, source)}: {attribute} {error}")
                continue
            if target is None:
                continue
            if not target.is_file():
                errors.append(
                    f"{display(root, source)}: missing {attribute} target {reference}"
                )
                continue
            fragment = urllib.parse.urlsplit(reference).fragment
            if fragment:
                target_page = pages.get(target.resolve())
                if target_page is None:
                    errors.append(
                        f"{display(root, source)}: fragment targets non-HTML {reference}"
                    )
                elif urllib.parse.unquote(fragment) not in target_page.ids:
                    errors.append(
                        f"{display(root, source)}: missing fragment target {reference}"
                    )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print(f"FAIL: generated site does not exist: {root}")
        return 1

    errors = sorted(set(check(root)))
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        print(f"generated-site validation failed with {len(errors)} error(s)")
        return 1
    print(f"generated-site validation passed: {len(list(root.rglob('*.html')))} pages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
