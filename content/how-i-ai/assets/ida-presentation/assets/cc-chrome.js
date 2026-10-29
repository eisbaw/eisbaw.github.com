// The Claude Code chrome of the IDA deck, browser only (theme/ida.css has the looks).
//
// Once, for every slide: a status line under the prompt (section, a progress bar for the deck that
// turns from green to yellow at 50 % and to red at 80 %, the talk clock, the slide, the number of
// bullets as agents), and the travelling ✻ and the cover it pulls down.
//
// The cover's character grid flickers, a few cells at a time, while the cover is on screen.
//
// Each time a slide becomes active: the title's ✻ leaves the title and sweeps down the left margin
// in half a second, uncovering the slide; every bullet appears queued (open circle), starts running
// (solid white, pulsing, "⎿ running…") and finishes on its own time, out of order (green,
// "⎿ done"); the ✻ lands above the prompt and keeps spinning, with Claude Code's spinner text,
// until the last bullet is done. The finish order is a fixed shuffle per slide, so rehearsals repeat.
// Leaving the slide cancels it all, so the slide rests finished, which is also what the PDF and the
// presenter's next-slide preview show. Nothing runs under reduced motion.
(() => {
  const SWEEP = 500, START = 40, LEAD = 40, SPAWN_TO_RUN = 140, DONE_FROM = 800, DONE_TO = 1500, PULSE = 260;
  const deck = document.querySelector('.bespoke-marp-parent');
  if (!deck || document.body.dataset.bespokeView === 'next') return;
  const slides = [...deck.querySelectorAll('svg.bespoke-marp-slide')];
  const sections = slides.map((slide) => slide.querySelector('section'));
  const total = sections.length;
  const talk = sections.filter((s) => !s.classList.contains('backup')).length;   // backup slides follow Q&A
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const bullets = (section) => (section.classList.contains('no-agents') ? [] : [...section.querySelectorAll('.copy li')]);
  // Geometry and colours come from the theme (theme/ida.css), read once.
  const theme = getComputedStyle(sections[0]);
  const css = (name) => theme.getPropertyValue(name).trim();
  const PROMPT_TOP = 720 - parseFloat(css('--prompt-bottom')) - parseFloat(css('--prompt-height'));
  const INK = css('--ink'), TEXT = css('--text'), GREEN = css('--green');
  const animated = (section) => section.querySelector('h1') && !section.classList.contains('cover') && !section.classList.contains('closing');

  // ---- the status line ----
  const html = (cls, text) => `<span class="${cls}">${text}</span>`;
  const elapsed = () => {   // talk-timing.js publishes the talk's start on the deck element
    const start = Number(deck.dataset.talkStart) || 0;
    const s = start ? Math.max(0, Math.floor((Date.now() - start) / 1000)) : 0;
    return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}s`;
  };
  const statusLine = (section, index) => {
    const p = talk > 1 ? Math.min(1, index / (talk - 1)) : 1;
    const cells = Math.floor(p * 10), tone = p < .5 ? 'p-green' : p < .8 ? 'p-yellow' : 'p-red';
    const open = section.querySelector('header a.on');
    const where = open ? `${open.textContent.replace(/\.md$/, '')}/` : '~/';
    const agents = bullets(section).length;
    return '<div>' + [
      html('s-org', 'IDA'), ' ', html('s-path', 'how-i-ai/35m'), ' ',
      `<span class="s-bar ${tone}">${'█'.repeat(cells)}<u>${'░'.repeat(10 - cells)}</u></span>`, html(tone, `${Math.round(p * 100)}%`), '  ',
      html('s-sec', `▸ ${where}`), '  ', html('s-time', `⏱ <b class="cc-elapsed">${elapsed()}</b>`), '  ', html('s-slide', `◷ ${index + 1}/${total}`),
    ].join('') + '</div><div>' + [
      html('s-mode', '⏵⏵ talk mode on'), html('s-dot', ' · '), html('s-spk', '1 speaker'),
      agents ? html('s-dot', ' · ') + html('s-agents', `← ${agents} agents`) : '',
    ].join('') + '</div>';
  };
  sections.forEach((section, index) => {
    const status = document.createElement('div');
    status.className = 'cc-status';
    status.innerHTML = statusLine(section, index);
    section.appendChild(status);
    section.classList.add('cc-has-status');
    if (animated(section)) {
      for (const cls of ['cc-cover', 'cc-star']) {
        const el = document.createElement('div');
        el.className = cls;
        el.setAttribute('aria-hidden', 'true');
        section.appendChild(el);
      }
    }
  });

  // ---- the arrival ----
  const stop = (section) => {
    for (const a of section.getAnimations({ subtree: true })) if (a.id === 'cc') a.cancel();
    section.classList.remove('cc-run');
  };
  const run = (section) => {
    stop(section);
    if (reduceMotion.matches || !animated(section)) return;
    const box = section.getBoundingClientRect(), k = box.width / 1280;
    const y = (el) => (el.getBoundingClientRect().top - box.top) / k;
    const h = section.querySelector('h1'), hs = getComputedStyle(h), hb = h.getBoundingClientRect();
    const sx = (hb.left - box.left) / k + parseFloat(hs.borderLeftWidth) + parseFloat(hs.paddingLeft);
    const sy = (hb.top - box.top) / k + parseFloat(hs.borderTopWidth) + parseFloat(hs.paddingTop) + (parseFloat(hs.lineHeight) - 32) / 2;
    const cy = (hb.bottom - box.top) / k + 6;
    const bandTop = PROMPT_TOP, landY = bandTop - 38;
    const items = bullets(section);
    const spawn = items.map((li) => START + SWEEP * Math.min(1, Math.max(0, (y(li) - LEAD - sy) / (landY - sy))));
    const runAt = spawn.map((t) => t + SPAWN_TO_RUN);
    let seed = items.reduce((a, li) => a + li.textContent.length, 7);
    const rand = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
    const slots = items.map((_, i) => DONE_FROM + (DONE_TO - DONE_FROM) * (items.length > 1 ? i / (items.length - 1) : 0));
    for (let i = slots.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [slots[i], slots[j]] = [slots[j], slots[i]]; }
    const done = slots.map((t, i) => Math.max(t, runAt[i] + 250));
    const last = Math.max(START + SWEEP, ...done);

    const star = section.querySelector('.cc-star'), cover = section.querySelector('.cc-cover');
    star.style.left = `${sx}px`;
    section.style.setProperty('--start', `${START / 1000}s`);
    section.style.setProperty('--flow', `${(last - START) / 1000}s`);
    section.classList.add('cc-run');
    const opts = (extra) => ({ duration: START + SWEEP, fill: 'both', easing: 'linear', id: 'cc', ...extra });
    const hold = START / (START + SWEEP);
    star.animate([{ top: `${sy}px` }, { top: `${sy}px`, offset: hold }, { top: `${landY}px` }], opts());
    cover.animate([{ top: `${cy}px` }, { top: `${cy}px`, offset: hold }, { top: `${bandTop}px` }], opts());

    // Claude Code's spinner text beside the landed ✻
    const secs = (ms) => `${(ms / 1000).toFixed(1)}s`, n = items.length, land = START + SWEEP;
    const words = [{ content: '""', offset: 0 }, { content: '""', offset: land / (last + 1) }];
    for (let t = land; t < last; t += 100) {
      const left = n - done.filter((d) => d <= t).length;
      words.push({ content: `"Checking off… (${secs(t)} · ← ${left} agents)"`, offset: t / (last + 1) });
    }
    words.push({ content: n ? `"Done (${secs(last)} · ${n} agents)"` : `"Done (${secs(last)})"`, offset: 1 });
    star.animate(words, { duration: last + 1, fill: 'both', easing: 'linear', pseudoElement: '::after', id: 'cc' });

    // each bullet: queued (open), running (white, pulsing), done (green)
    const OPEN = { background: 'transparent', borderColor: TEXT, opacity: 1 };
    const WHITE = { background: INK, borderColor: INK };
    const DONE = { background: GREEN, borderColor: GREEN, opacity: 1 };
    items.forEach((li, i) => {
      const end = done[i] + 120, at = (ms) => Math.min(1, ms / end);
      const finished = JSON.stringify(`⎿  ${li.dataset.done || 'done'}`);   // a bullet's own ⎿ line, else "done"
      const dot = [{ ...OPEN, offset: 0 }, { ...OPEN, offset: at(runAt[i]) }];
      for (let t = runAt[i] + 60, on = true; t < done[i]; t += PULSE, on = !on) dot.push({ ...WHITE, opacity: on ? 1 : .45, offset: at(t) });
      dot.push({ ...WHITE, opacity: 1, offset: at(done[i]) }, { ...DONE, offset: 1 });
      li.animate(dot, { duration: end, fill: 'both', easing: 'linear', pseudoElement: '::before', id: 'cc' });
      li.animate([
        { content: '"⎿  running…"', opacity: 0, offset: 0 },
        { content: '"⎿  running…"', opacity: 0, offset: at(runAt[i]) },
        { content: '"⎿  running…"', opacity: 1, offset: at(runAt[i] + 80) },
        { content: '"⎿  running…"', opacity: 1, offset: at(done[i]) },
        { content: finished, opacity: 1, offset: at(done[i] + 1) },
        { content: finished, opacity: 1, offset: 1 },
      ], { duration: end, fill: 'both', easing: 'linear', pseudoElement: '::after', id: 'cc' });
    });
  };

  // ---- follow the active slide ----
  let current = -1;
  const sync = () => {
    const index = slides.findIndex((slide) => slide.classList.contains('bespoke-marp-active'));
    if (index === current) return;
    if (current >= 0) stop(sections[current]);
    current = index;
    if (index >= 0) run(sections[index]);
  };
  new MutationObserver(sync).observe(deck, { attributes: true, attributeFilter: ['class'], subtree: true });
  sync();
  // ---- the cover's character grid flickers while the cover is on screen ----
  // A cell takes the character from the same column in another row, so the grid in slides.md (written
  // by tools/cover_grid.py) stays the only definition of its density.
  const grid = deck.querySelector('section.cover .cover-grid');
  if (grid && !reduceMotion.matches) {
    const rows = grid.textContent.split('\n').map((line) => [...line]);
    const cols = Math.min(...rows.map((r) => r.length));
    const pick = (n) => Math.floor(Math.random() * n);
    setInterval(() => {
      if (current < 0 || !sections[current].classList.contains('cover')) return;
      for (let k = 0; k < 14; k++) {
        const c = pick(cols);
        rows[pick(rows.length)][c] = rows[pick(rows.length)][c];
      }
      grid.textContent = rows.map((r) => r.join('')).join('\n');
    }, 160);
  }
  const tick = () => {
    if (current < 0) return;
    const clock = sections[current].querySelector('.cc-elapsed');
    if (clock) clock.textContent = elapsed();
  };
  setInterval(tick, 1000);
  // when the talk clock is reset or its head dragged, follow at once
  new MutationObserver(tick).observe(deck, { attributes: true, attributeFilter: ['data-talk-start'] });
})();
