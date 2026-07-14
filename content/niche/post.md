**This blog runs on a static-site engine that treats Nix as the build system, not just the package manager.** It is called niche. A small Rust binary does the text work; a <span class="gloss" tabindex="0">Nix flake<span class="gloss-card"><span class="gc-head"><span class="gc-name">Nix flake</span></span><span class="gc-body">A self-contained unit of Nix code with pinned inputs and a standard output schema, giving reproducible builds.</span></span></span> orchestrates everything else and caches the result.

I wrote this for people who like their tools boring and their rebuilds fast. If you have ever waited on a site generator to re-render 300 unchanged posts because you fixed one typo, this is the design that fixes it.

niche is the **engine**. This blog is an **instance**: a separate repo that holds the content and a theme, and calls `niche.lib.mkSite`. The [[about-blog]] post covers the instance side. This post is the engine.

## Architecture: compile, link, compose

The build is a **compiler toolchain**, modelled on `cc` + `ld`.

![Build pipeline: compile, link, compose](assets/pipeline.svg)

**Compile.** Each post is its own Nix <span class="gloss" tabindex="0">derivation<span class="gloss-card"><span class="gc-head"><span class="gc-name">Derivation</span></span><span class="gc-body">One build step in Nix: an input-addressed recipe whose output is fully determined by its inputs.</span></span></span>. A Rust binary, `post2html render`, turns Markdown into an HTML fragment. Posts know nothing about each other, so Nix builds them in parallel.

**Link.** One pass resolves cross-references. Posts link to each other the way <span class="gloss" tabindex="0">Obsidian<span class="gloss-card"><span class="gc-head"><span class="gc-name">Obsidian</span></span><span class="gc-body">A Markdown note-taking app whose double-bracket [[wiki-link]] convention niche borrows for cross-post links.</span><span class="gc-foot"><a href="https://obsidian.md" target="_blank" rel="noopener">obsidian.md</a></span></span></span> does: a slug wrapped in double square brackets. This sentence links to the [[about-blog]] colophon exactly that way. Render leaves each link as an unresolved placeholder; `post2html link` swaps in a real `<a href>` using a registry built from every post's metadata. A slug that resolves gets the target's title as its text. A slug that does not gets marked broken and warned about on stderr.

**Compose.** The final assembly. `post2html compose` wraps each fragment in site chrome (nav, footer, `<head>`), generates the aggregate pages (paginated index, tag pages, archive, Atom feed), and copies static assets.

The split is the point. Change one post and only that post's compile derivation reruns. Link and compose rerun too, but they are cheap: string replacement and templating, no content parsing.

## The Nix layer

**Nix is the orchestration language.** There is no YAML, no TOML, no bespoke config format. Your metadata is a Nix expression, and so is the build graph.

![Nix layer: how site.nix orchestrates the build](assets/nix-layer.svg)

- **`meta.nix`** — each post's metadata as a pure attribute set: title, date, tags, summary. This is the single source of truth.
- **`mkPost.nix`** — a shared build function. Hand it a post directory, get back `{ meta; compiled; }`. No per-post boilerplate. If the post ships a `figures.nix`, it is built and its output is merged into that post's `assets/`.
- **`resolveContent.nix`** — content-file detection by extension priority: `.md` > `.rst` > `.html` > `.txt`. Written once, used everywhere.
- **`site.nix`** — the top-level expression. It discovers posts, checks slugs are unique, validates nav links, builds the link registry, and drives all three phases.

Nix hands you caching for free. Each compiled post is a <span class="gloss" tabindex="0">store path<span class="gloss-card"><span class="gc-head"><span class="gc-name">Store path</span></span><span class="gc-body">An immutable /nix/store/&lt;hash&gt; build output, keyed by a hash of its inputs so nothing rebuilds unless an input changes.</span></span></span>. Nothing changed means nothing rebuilds. The public surface is one function: `niche.lib.mkSite { pkgs; contentDir; siteConfig; themeDir; }` returns the built site as a derivation.

## The Rust binary

`post2html` is deliberately **Nix-agnostic**. It takes a JSON config plus a content file and emits HTML plus JSON metadata. A Makefile could drive it. It neither knows nor cares that Nix exists.

Three subcommands, each a pure function:

- **`render`** — Markdown, RST, HTML, or plain text to an HTML fragment. Syntax highlighting via <span class="gloss" tabindex="0">syntect<span class="gloss-card"><span class="gc-head"><span class="gc-name">syntect</span></span><span class="gc-body">A Rust syntax-highlighting library that uses Sublime Text grammar and theme definitions.</span><span class="gc-foot"><a href="https://github.com/trishume/syntect" target="_blank" rel="noopener">github.com/trishume/syntect</a></span></span></span>. Wiki-links left as placeholders.
- **`link`** — resolve those placeholders against the JSON registry. Warn on anything broken.
- **`compose`** — wrap fragments in <span class="gloss" tabindex="0">Tera<span class="gloss-card"><span class="gc-head"><span class="gc-name">Tera</span></span><span class="gc-body">A Rust template engine with Jinja2-like syntax, used here for the site chrome and aggregate pages.</span><span class="gc-foot"><a href="https://keats.github.io/tera" target="_blank" rel="noopener">keats.github.io/tera</a></span></span></span> templates, build the aggregate pages, copy static assets.

Markdown goes through <span class="gloss" tabindex="0">comrak<span class="gloss-card"><span class="gc-head"><span class="gc-name">comrak</span></span><span class="gc-body">A Rust CommonMark and GitHub-Flavored-Markdown parser and renderer.</span><span class="gc-foot"><a href="https://github.com/kivikakk/comrak" target="_blank" rel="noopener">github.com/kivikakk/comrak</a></span></span></span> (<span class="gloss" tabindex="0">CommonMark<span class="gloss-card"><span class="gc-head"><span class="gc-name">CommonMark</span></span><span class="gc-body">A strongly specified, unambiguous standard dialect of Markdown.</span><span class="gc-foot"><a href="https://commonmark.org" target="_blank" rel="noopener">commonmark.org</a></span></span></span> + GFM). RST shells out to `rst2html5` from docutils. HTML passes through. Plain text gets wrapped in `<pre>`.

| Format | Extension | How |
|--------|-----------|-----|
| **Markdown** (CommonMark + GFM) | `.md` | comrak: tables, autolinks, task lists, strikethrough |
| **reStructuredText** | `.rst` | shells out to `rst2html5` |
| **Raw HTML** | `.html` | passthrough |
| **Plain text** | `.txt` | wrapped in `<pre>` |

## Themes never touch a post

A theme is a directory of Tera templates plus CSS and fonts. niche bundles two, `fancy-sidebar` and `plain`; an instance points `themeDir` at its own.

![Theme structure](assets/theme-structure.svg)

The Rust binary does not know themes exist. Templates are read only during compose. So editing a template or a stylesheet **never rebuilds a single post**: only the compose phase reruns. That is the whole reason theming is fast.

## Performance, and the bug that taught it

niche was profiled against a synthetic corpus of **305 posts**. The shipped design does a full cold build in about **12 seconds** and an incremental build (one post changed) in about **2.3 seconds**. A warm build, nothing changed, is a Nix cache hit: no post is rebuilt at all.

Those numbers are the payoff of a mistake. The first version filtered the Rust crate with `cleanSource ./.`, which pulled the content directory into the binary's source hash. Editing any post changed that hash, which invalidated the binary, which invalidated all 305 post derivations. An incremental rebuild took **1 minute 58 seconds**.

The fix was to filter the source to `Cargo.toml`, `Cargo.lock`, and `src/` only. Content and theme changes stop touching the binary. Two minutes became two seconds.

## What the AI got wrong

niche was designed and written by an AI (Claude, Opus), working interactively with a human (Mark). The PRD, the Rust, the Nix, the templates, the tests: all generated, all reviewed. Each milestone passed an architectural-review agent and a QA agent before it was committed.

The interesting part is the mistakes, because review caught them:

- **`cleanSource ./.`** folded content into the binary hash and killed incremental builds. Fixed with a narrow source filter (above).
- **Batched compilation.** Fifty posts per derivation was faster cold (3.6s vs 12s) but identical incrementally (2.3s), and it duplicated the content-resolution logic and leaked a batch-addressing abstraction onto every consumer. Reviewed, rejected, deleted.
- **`links.json` fed into every post derivation** defeated per-post caching: one new post dirtied them all. Redesigned into the compile/link/compose split above.
- **Shell-interpolated JSON** would have broken on any title containing a quote. Config now goes to the store as a file and is passed by path, never spliced into a shell string.

The suite that guards all this is over a hundred Rust unit and integration tests plus a flake `e2e` check that smoke-builds a fixture site. None of it stopped the four bugs above from being written. Review did.

## Where it stands

niche is small, and it is scoped to one job: a personal, text-first blog built by Nix. It is not a general CMS, it has no plugin system, and it will not import your WordPress. That narrowness is why the whole build graph fits in your head.

Source: the engine, its PRD, its backlog, and the commit history of every decision live in the `niche` repo at [github.com/eisbaw/niche](https://github.com/eisbaw/niche). This blog is a thin instance on top of it: see the [[about-blog]] colophon for how the two fit together. Clone niche, run `nix build` on the fixture site, and change one post to watch the cache do its job.
