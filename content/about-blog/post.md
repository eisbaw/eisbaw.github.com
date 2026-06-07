# About This Blog

This entire blog — the **Rust binary**, the **Nix build system**, the **templates**, the **CSS**, this very text — was designed and implemented by an **AI (Claude)**, working interactively with a **human (Mark)**. Every line of code was reviewed, and every architectural decision was debated. **Nothing was copy-pasted from a tutorial.**

## Architecture: Compile, Link, Compose

The build follows a **compiler toolchain model**, analogous to `cc` + `ld`:

![Build pipeline: compile, link, compose](assets/pipeline.svg)

1. **Compile** — Each post is an **independent Nix derivation**. A Rust binary (`post2html render`) converts Markdown to an **HTML fragment**. Posts know nothing about each other. **Nix builds them in parallel.**

2. **Link** — A single pass resolves **cross-references**. Posts can link to each other using Obsidian-style `[[wiki-links]]`. The render phase leaves these as **unresolved placeholders**; the link phase (`post2html link`) replaces them with real `<a href>` tags using a **registry built from all posts' metadata**.

3. **Compose** — The final assembly. `post2html compose` wraps each content fragment in **site chrome** (navigation, footer, `<head>` tags), generates **aggregate pages** (index with pagination, tag pages, archive, Atom feed), and copies static assets.

This separation matters for **performance**: changing one post **only rebuilds that post's** compile derivation. The link and compose phases re-run but are fast — string replacement and template rendering, no content parsing.

## The Nix Layer

**Nix is the orchestration language**, not just the package manager. There is **no YAML, TOML, or custom config format**.

![Nix layer: how site.nix orchestrates the build](assets/nix-layer.svg)

- **`meta.nix`** — Each post's metadata is a **pure Nix attribute set**. Title, date, tags, summary — all Nix expressions. This is the **single source of truth**.
- **`mkPost.nix`** — A **shared build function**. Takes a post directory, returns `{ meta; compiled; }`. **No per-post boilerplate.**
- **`resolveContent.nix`** — Content file detection by extension priority (`.md` > `.rst` > `.html` > `.txt`). **Written once, used everywhere.**
- **`site.nix`** — The **top-level expression**. Discovers posts, validates slug uniqueness, validates nav links, builds the link registry, and orchestrates all three phases.

Nix gives us **caching for free**. Each compiled post is a **store path**. If the content hasn't changed, Nix skips the rebuild. A warm build (nothing changed) takes **0.7 seconds** for 305 posts.

## The Rust Binary

`post2html` is deliberately **nix-agnostic**. It takes **JSON config + a content file** and produces **HTML + JSON metadata**. It could be driven by a Makefile or a shell script — it doesn't know or care that Nix exists.

Three subcommands, each a **pure function**:

- **`render`** — Markdown/RST/HTML/txt to HTML fragment. **Syntax highlighting** via syntect. Wiki-link placeholders.
- **`link`** — Resolve wiki-link placeholders using a **JSON registry**. Warn on broken links.
- **`compose`** — Wrap fragments in **Tera templates**, generate aggregate pages, copy static assets.

## Content Formats

| Format | Extension | How |
|--------|-----------|-----|
| **Markdown** (CommonMark + GFM) | `.md` | comrak with tables, autolinks, task lists, strikethrough |
| **reStructuredText** | `.rst` | Shells out to `rst2html5` from docutils |
| **Raw HTML** | `.html` | Passthrough |
| **Plain text** | `.txt` | Wrapped in `<pre>` |

## Design Principles

The visual design is **typography-first**: generous whitespace, a minimal color palette, and nothing competing with the text.

- **Inter** for body text, **JetBrains Mono** for code. **Self-hosted** as woff2.
- **Dark mode** with a small toggle, persisted in `localStorage`, defaulting to your OS preference.
- No CSS framework. **CSS custom properties** for theming. One `main.css`, one `code.css`.
- **Valid HTML5**. Semantic elements. **OpenGraph tags**. Atom feed. Canonical URLs.
- **Minimal JavaScript** — just the dark-mode toggle, plus [MathJax](https://www.mathjax.org/) for rendering math. The content itself is **static HTML + CSS**.

## Theming

![Theme structure](assets/theme-structure.svg)

A theme is just a directory of **Tera templates + CSS** (here, a sidebar layout with a MathJax include). Switching themes means pointing the instance's `themeDir` at a different directory. The Rust binary **doesn't know about themes** — templates are only used during compose. This means **changing a template or CSS never rebuilds any post**, only the compose phase.

## Build Performance (305 posts)

| Scenario | Time |
|----------|------|
| **Full cold build** | ~12s |
| **Incremental** (1 post changed) | **2.2s** |
| **Warm** (nothing changed) | **0.7s** |

The **source filter** in `site.nix` ensures content changes **never rebuild the Rust binary**. Only the changed post recompiles.

## What AI Built

The PRD, the architecture, the Rust code, the Nix expressions, the templates, the CSS, the **106 tests** (unit + integration, 14 E2E assertions), the backlog, the commit messages — **all generated by Claude (Opus)**, guided by Mark through iterative review. Each milestone was reviewed by an **MPED architectural agent** and a **QA agent** before committing.

The AI made **real mistakes** along the way:
- Initially had `cleanSource ./.` which **included content files in the Rust binary hash**, making incremental builds useless
- Tried a **batched compilation** approach (50 posts per derivation) that was faster for cold builds but **worse in every other dimension** — reviewed, rejected, deleted
- Fed `links.json` into every post derivation, **defeating per-post caching** — redesigned to the compile/link/compose pipeline
- **Shell-interpolated JSON strings** that would break on titles with quotes

Each mistake was **caught by review and fixed properly**. The codebase is better for it.

## Source

The full source — including the **PRD**, **backlog**, and **commit history** of every design decision — is in the repository. `git log` tells the complete story.
