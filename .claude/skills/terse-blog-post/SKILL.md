---
name: terse-blog-post
description: Write or revise a blog post for this site (eisbaw / radix63, niche engine) in the house voice: a teaching voice that leads with a flat bolded claim, writes in first and second person, uses medium sentences with short punches and blunt verdicts, bans long em-dashes, grounds every claim in an example, and ships with diagrams. Use when creating a new content/<slug>/ post, rewriting a draft that reads too long or too academic, or editing a post's prose. Captures the writing style and the niche build/preview mechanics.
---

# House voice (blog)

This is a teaching voice. You are the author, talking straight to one reader,
explaining something you understand and they want. Lead with the claim, ground
every abstraction in an example, and stop when the reader can do the thing. Cut
anything that does not teach.

## The voice

**Open with a flat, bolded claim.** The first line is bolded and states what the
thing is or is worth. No runway, no background, no throat-clearing.

**Say why you wrote it and who for.** Usually the second paragraph, one or two
sentences. This grounds your authority without claiming it.

**Write in the first person and own your opinions.** "I wanted", "I was sure",
"the wire won". Take a side.

**Talk to the reader.** Use "you" and imperatives: "Decompile it and look." "Watch
the wire."

**Use rhetorical questions to turn corners.** "So where does the video go?" Then
answer it.

**Medium sentences are the backbone**, roughly 12 to 20 words. Vary the length:
about 15% very short, 55% medium, 30% long. Never stack two long sentences without
a short one to land the point.

**Drop short punches for emphasis**, sometimes a whole paragraph. "The wire won."
"Philips wrote almost none of it."

**Short paragraphs, with room to breathe.** Most are two to four sentences. Let one
run longer when you are explaining a single thing. White space between every
paragraph.

**Bold only the few load-bearing phrases.** Bold for emphasis, but only the most
important things. If half the post is bold, none of it is.

**Land one or two blunt, quotable verdicts per piece.** Earn them. "C++ is a
necessary evil."

**Cut every intensifier and every hedge.** No "very, truly, exactly, deliberately,
genuinely". No "it could be argued that". State the verdict instead. No marketing.

**No long em-dashes.** The "—" is banned. Use a colon, parentheses, a hyphen, or
split the sentence. Plain hyphens and parenthetical asides are fine and welcome.

**Use colons, semicolons, and parentheses freely.** Colons introduce a list or the
payoff of a setup; semicolons chain tight clauses; parentheses carry asides.

**A rare "!" is allowed**, for real excitement, never for hype.

**Plain verbs, no jargon.** Explain a term on first use, or pick a simpler term.
Tie every abstract claim to a concrete example, a number, or code.

**State the scope plainly.** One sentence for who and what it is for. A short
bullet list for what it is NOT for, without apology.

**No sustained metaphor.** Say the thing directly.

**Headers do the connecting.** Skip "Furthermore / However / In conclusion". Let the
section structure carry the logic.

## Structure

Length: as long as it needs, up to about three pages. Most posts are shorter. Stop
when the reader can do the thing. Do not pad to fill, and do not cut what teaches.

A good default arc for a technical post:

1. **The claim**: bolded first line, then why you wrote it and who for.
2. **What it is**: the thing in one move, two parts, or two files.
3. **How it works / how you did it**: grounded in examples, code, or a diagram.
4. **Why it matters / where it stands**: the payoff, plus honest caveats as a short
   bullet list.

End with a `Source:` line and a forward push: the next step, the door you just
opened, what the reader should go do. No recap.

When the post is about code, keep code snippets: the smallest example that proves
the claim, interleaved with the prose.

## Diagrams

Include one or two. Hand-author SVG into `content/<slug>/assets/` (no LaTeX needed;
niche copies `assets/` verbatim). A `figures.nix` building TikZ->SVG also works but
is heavier, so prefer plain SVG.

Colour diagrams to read on **both light and dark** themes: light-filled cards (e.g.
`#eef2ff`, `#fffbeb`, `#f9fafb`) with mid-grey borders (`#9ca3af`) and dark text
inside the cards. Avoid pure-black strokes and avoid relying on the page background.
`<img>`-embedded SVG does not inherit `currentColor`, so do not depend on it. A
simple, robust trick: give the whole SVG a light panel background so all text reads
on either theme.

Reference from Markdown: `![alt text](assets/name.svg)`.

## Before / after (the edits this voice encodes)

- "A parallel algorithm is rarely written once. The same stencil blur, blocked
  matrix multiply, or small neural-network forward pass is expected to run on a
  laptop using OS threads, to scale out across a message-passing cluster, and to
  run on an embedded microcontroller..." (one 90-word sentence)
  -> "**Algorithms outlive the hardware they run on, yet every time we must port
  or performance tune.** A signal-processing kernel stays stable for years. The
  chips under it come and go." (flat bolded claim, split sentences)

- "the compiler infers and synthesises every cross-worker transfer"
  -> "the compiler writes the data transfers for you" (plain verbs)

- "One can observe that the static analysis was subsequently invalidated by the
  empirical capture." -> "I watched the wire. It was my own bug." (first person,
  short punch, blunt verdict)

- "It may be worth considering decompiling the application." -> "Decompile it and
  look." (imperative, no hedge)

## Post mechanics (niche engine)

A post is a directory under `content/<slug>/`:

- `meta.nix`: `{ slug; title; date; tags; summary; authors; }`. The `title` and
  `summary` are the single source of truth (the H1 in `post.md` should match the
  title). `summary` is the listing/OG blurb.
- `post.md`: CommonMark + GFM. Start with the `# H1` matching the title.
- `assets/`: optional, copied verbatim (put SVGs here).

niche discovers any `content/<dir>/` that contains a `meta.nix`. There is **no
date filter**.

### The flake gotcha: always `git add` new files

`nix build` only sees **git-tracked** files. A brand-new `content/<slug>/`
directory is invisible to the build until staged. After creating or adding files
(post.md, meta.nix, assets/), run `git add content/<slug>/` before building, or
the post will silently not appear.

### Build and preview

A `justfile` at the repo root drives it (run inside the dev shell, which provides
`just` and `python3`):

```
nix develop -c just serve   # stop prior preview, rebuild, serve on :8099
nix develop -c just build   # just rebuild into ./result
nix develop -c just stop    # kill the ad-hoc preview server
```

`just serve` runs `stop` then `build` then serves `./result`, so re-running it
picks up edits. Hard-refresh the browser (Ctrl-Shift-R), because static SVG/HTML
caches aggressively. Note: the ad-hoc server resolves the `result` symlink at
launch, so after a rebuild you may need to restart it to serve the fresh build. Do
not commit or push unless asked.
