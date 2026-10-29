// Staged figure reveals, browser deck only.
//
// Each figure SVG wraps its drawing in <g id="play"> and animates its stages only under
// #play:target, so the file shows the complete figure unless it is loaded with the fragment.
// Chromium keeps one SVG document, with one animation clock, per image URL: a figure loaded as
// "x.svg#play" plays once, from the moment that URL is first used, and never again. So on every
// slide activation the figure is reloaded under a URL nobody has used before, and its stages
// run from that moment however long the deck has been open. Going back to a slide replays it.
//
// Nothing happens in the PDF (Marp's bare template has no active slide), under reduced motion,
// or in the presenter's next-slide preview. Printing from the browser restores the static files.
(() => {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const plain = (img) => img.getAttribute('src').split(/[?#]/)[0];
  const figures = (root) => [...root.querySelectorAll('.figure img')].filter((img) => plain(img).endsWith('.svg'));

  const play = (slide) => {
    if (reduceMotion.matches || document.body.dataset.bespokeView === 'next') return;
    for (const img of figures(slide)) img.src = `${plain(img)}?t=${Date.now()}#play`;
  };
  const restore = () => {
    for (const img of figures(document)) if (img.getAttribute('src') !== plain(img)) img.src = plain(img);
  };

  const deck = document.querySelector('.bespoke-marp-parent');
  if (!deck) return;
  const isActive = (slide) => slide.classList.contains('bespoke-marp-active');
  const update = (slide) => {
    if (isActive(slide) && !slide.dataset.playing) {
      slide.dataset.playing = '1';
      play(slide);
    } else if (!isActive(slide)) {
      delete slide.dataset.playing;
    }
  };
  new MutationObserver((records) => {
    for (const { target } of records) if (target.matches('svg.bespoke-marp-slide')) update(target);
  }).observe(deck, { attributes: true, attributeFilter: ['class'], subtree: true });
  for (const slide of deck.querySelectorAll('svg.bespoke-marp-slide')) update(slide);
  addEventListener('beforeprint', restore);
})();
