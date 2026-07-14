---
name: ui-review
description: Visually review the rendered UI of this blog (radix63 / niche) at both desktop and phone viewports. Screenshots the running site with headless Firefox (Brave headless hangs here), then inspects for horizontal overflow, glossary-callout clipping, sticky panes, sidebar layout, sprites/figures, and light/dark themes. Use when asked to render, preview, screenshot, or check how a page looks (especially on mobile), or after any CSS/theme/template change.
---

# UI review (blog)

Render the site at real viewport sizes, look at the pixels, and check the layout
holds. Always review **desktop and phone**, not just one. A change that looks fine
at 1280px can overflow at 390px, and vice versa.

## Prerequisites

The preview server must be running (serves `./result` on port 8099):

```
nix develop -c just serve   # stop prior server, rebuild, serve on :8099
```

`just serve` runs in the background and blocks until it answers, so a screenshot
step right after it is safe. If a build changed files, re-run `just serve` (the
ad-hoc server resolves the `result` symlink at launch).

## Screenshot recipe (the reliable path)

Use **headless Firefox**. It honours `--window-size` as the exact viewport and
exits after writing the PNG. Then view the PNG.

```
SS=<scratchpad-dir>
prof=$(mktemp -d "$SS/ff.XXXXXX")
timeout 90 firefox --headless --new-instance -profile "$prof" \
  --window-size=390,844 --screenshot "$SS/phone.png" "http://127.0.0.1:8099/"
```

- **Phone**: `--window-size=390,844` (iPhone-class). This is the true mobile
  layout, below the site's breakpoints.
- **Desktop / regular PC**: `--window-size=1280,900` (and optionally
  `--window-size=1440,900`). Check the three-column layout: sidebar, content, and
  the "On this page" TOC (TOC appears only on post pages at wide widths).
- View the result with the Read tool (it renders images), and/or open it for the
  user with `feh "$SS/phone.png"`.

To review a specific page, point the URL at it, e.g.
`http://127.0.0.1:8099/posts/<slug>/`.

### Gotchas (learned the hard way)

- **Brave headless HANGS** in this environment in every mode (`--headless`,
  `=new`, `=old`) and never writes the PNG. Do not use it for screenshots. Use
  Firefox headless.
- **A visible Brave window clamps to ~500px** minimum width (Chromium limit), so
  you cannot get a true 390px *window*. For an exact phone viewport use Firefox
  headless (above), or a visible Firefox + Responsive Design Mode (Ctrl+Shift+M).
- **The sandbox SIGTERMs GUI launches** unless they are fully detached before the
  shell exits. Launch visible apps as:
  `{ env -u TMPDIR setsid <app> ... >/dev/null 2>&1 </dev/null & disown ; } & sleep 3; echo done`
- **Do not combine** a screenshot capture and a viewer (`feh`) launch in the same
  shell script — it tends to get killed. Capture in one step, open `feh` in the next.

## What to check

### Horizontal overflow (the top phone bug)
Nothing may cross the right edge; the page body must never scroll sideways
(project rule). At 390px, scan for content clipped or pushed off-screen. Classic
causes:
- A **flex row without `flex-wrap`** (tag lists, chip rows) forcing width.
- A **grid child without `min-width: 0`** — a `1fr` column won't shrink below its
  content's min-content, so a long title or an unwrapped row widens the card.
- A wide `<pre>`, table, or figure without its own `overflow-x: auto`.
- An absolutely-positioned popover (a glossary callout) spilling past the viewport.

Fix at the source (wrap, `min-width: 0`, per-element `overflow-x`). Do not paper
over it with `overflow-x: clip` on the reading column: that clips real content.
`overflow-x: clip` belongs on the **full-width `.layout`**, as a backstop, not on
`.post-content`.

### Glossary callouts
On post pages, hover/focus a `.gloss` term near the **left/right edge** of the text
pane: its card must show in full (it spills into the side gutter), not get cut. It
must also sit **above the sticky header** (`.gloss-card` z-index > header's 50).

### Sticky panes
Scroll a post page: the left **sidebar** and the right **TOC** must stay stuck.
`overflow: clip` (not `hidden`) on `.layout` preserves this.

### Sidebar (desktop)
Topic groups are compact, each with its currentColor mask icon before the label,
and the overflow scrollbar is thin/muted. On phone the sidebar collapses behind the
**Menu** toggle.

### Themes
Review **both light and dark**. The toggle stamps `data-theme` on the root; check
contrast, the accent, callout cards, and figures (figures bake a light panel, so
they stay bright in dark mode by design).

### Sprites and figures
Title sprites render before each post title (index + post page) and animate.
Inline SVG figures render and are not clipped.

## Report

State what you rendered (which pages, which viewports), what looks right, and any
defect with its likely CSS cause. When you change CSS to fix something,
**re-screenshot at the same viewport and confirm** before calling it fixed.
