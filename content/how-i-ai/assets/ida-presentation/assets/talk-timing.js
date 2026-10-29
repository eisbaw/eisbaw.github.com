// The talk clock, browser deck only: a vertical bar on every slide (where is the theme's call; the
// IDA deck puts it on the right edge) that fills over the whole slot from the moment the talk first
// leaves the cover. The slot is the script tag's data-total-minutes. Each slide owns a slot on the
// bar, from its planned start (the running sum of the tNNN classes) for its planned length, with a
// tick at the top; the current slide's own stretch is in the theme's accent colour, so the
// fill's head against that stretch shows ahead or behind, and the next tick shows how long the
// next slide gets. A slot is a link to its slide: hovering names it (number, title, length,
// planned start) and clicking goes there through the deck's own #N hash. The link adds one
// history entry, so Back returns to the slide the jump came from.
//
// State lives in sessionStorage, so a reload mid-talk keeps the clock; it is dropped after
// three hours. The fill's head is a handle: drag it up or down to set how far into the talk you are,
// and the clock runs on from there (drag it to the top to restart at 0:00). The start time is published as the deck element's data-talk-start (ms since the
// epoch, absent before the talk starts) for other scripts, such as a status line, to read. Press "r" to reset it. Nothing runs in the PDF (no active slide), in the
// presenter's next-slide preview, or in print (the theme hides the bar).
(() => {
  const tag = document.querySelector('script[src$="talk-timing.js"][data-total-minutes]');
  const TOTAL_SECONDS = Number(tag ? tag.dataset.totalMinutes : 40) * 60;
  const deck = document.querySelector('.bespoke-marp-parent');
  if (!deck || document.body.dataset.bespokeView === 'next') return;
  const slides = [...deck.querySelectorAll('svg.bespoke-marp-slide')];
  const sections = slides.map((slide) => slide.querySelector('section'));
  const seconds = sections.map((section) => {
    const name = [...section.classList].find((c) => /^t\d+$/.test(c));
    return name ? Number(name.slice(1)) : 60;
  });
  const starts = seconds.map((_, index) => seconds.slice(0, index).reduce((a, b) => a + b, 0));
  const percent = (value) => `${(value / TOTAL_SECONDS) * 100}%`;
  const clock = (value) => `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
  const titles = sections.map((section) => {
    const heading = section.querySelector('h1');
    return heading ? heading.textContent.replace(/\s+/g, ' ').trim() : '';
  });
  const tips = titles.map((title, index) =>
    `${index + 1} · ${title} · ${clock(seconds[index])} · from ${clock(starts[index])}`);

  sections.forEach((section, index) => {
    const bar = document.createElement('div');
    bar.className = 'talk-bar';
    const stretch = document.createElement('div');
    stretch.className = 'talk-segment';
    stretch.style.top = percent(starts[index]);
    stretch.style.height = percent(seconds[index]);
    bar.appendChild(stretch);
    starts.forEach((start, slide) => {
      const slot = document.createElement('a');
      slot.className = 'talk-slot';
      slot.href = `#${slide + 1}`;
      slot.tabIndex = -1;
      slot.dataset.tip = tips[slide];
      slot.style.top = percent(start);
      slot.style.height = percent(seconds[slide]);
      bar.appendChild(slot);
    });
    const fill = document.createElement('div');
    fill.className = 'talk-fill';
    bar.appendChild(fill);
    const head = document.createElement('div');
    head.className = 'talk-head';
    head.title = 'Drag to set the elapsed time; to the top restarts the clock';
    bar.appendChild(head);
    section.appendChild(bar);
  });

  const KEY = 'talk-timing';
  const fresh = () => ({ start: null, stamp: Date.now() });
  let state = fresh();
  try {
    const saved = JSON.parse(sessionStorage.getItem(KEY));
    if (saved && Date.now() - saved.stamp < 3 * 3600 * 1000) state = saved;
  } catch (e) { /* no storage: the clock still runs for this page view */ }
  const publish = () => { if (state.start === null) delete deck.dataset.talkStart; else deck.dataset.talkStart = String(state.start); };
  const save = () => {
    publish();
    state.stamp = Date.now();
    try { sessionStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* see above */ }
  };

  let current = -1;
  const enter = (index) => {
    current = index;
    if (state.start === null && index > 0) state.start = Date.now();
    save();
  };
  const paint = () => {
    if (current >= 0) {
      const inTalk = state.start === null ? 0 : (Date.now() - state.start) / 1000;
      sections[current].style.setProperty('--talk-progress', Math.min(1, inTalk / TOTAL_SECONDS).toFixed(4));
    }
    requestAnimationFrame(paint);
  };

  // Dragging the head: the elapsed time follows the pointer along the bar, and stays when released.
  let dragging = null;
  const setFromPointer = (event) => {
    const box = dragging.getBoundingClientRect();
    const fraction = Math.min(1, Math.max(0, (event.clientY - box.top) / box.height));
    state.start = Date.now() - fraction * TOTAL_SECONDS * 1000;
    save();
  };
  for (const head of deck.querySelectorAll('.talk-head')) {
    head.addEventListener('pointerdown', (event) => {
      event.preventDefault(); event.stopPropagation();
      dragging = head.parentElement;
      head.setPointerCapture(event.pointerId);
      head.classList.add('dragging');
      setFromPointer(event);
    });
    head.addEventListener('pointermove', (event) => { if (dragging) { event.stopPropagation(); setFromPointer(event); } });
    const end = (event) => { if (!dragging) return; event.stopPropagation(); dragging = null; head.classList.remove('dragging'); };
    head.addEventListener('pointerup', end);
    head.addEventListener('pointercancel', end);
    head.addEventListener('click', (event) => event.stopPropagation());
  }

  const activeIndex = () => slides.findIndex((slide) => slide.classList.contains('bespoke-marp-active'));
  new MutationObserver(() => {
    const index = activeIndex();
    if (index >= 0 && index !== current) enter(index);
  }).observe(deck, { attributes: true, attributeFilter: ['class'], subtree: true });
  if (activeIndex() >= 0) enter(activeIndex());
  addEventListener('keydown', (event) => {
    if (event.key !== 'r' || event.ctrlKey || event.metaKey || event.altKey) return;
    state = fresh();
    if (current > 0) state.start = Date.now();
    save();
  });
  requestAnimationFrame(paint);
})();
