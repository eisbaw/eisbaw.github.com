(() => {
  let dialog;

  document.addEventListener('click', (event) => {
    const link = event.target.closest('.zoom-thumbnail a');
    const thumbnail = link?.querySelector('img');
    if (!thumbnail) return;
    event.preventDefault();
    event.stopPropagation();
    if (dialog?.open) return;

    dialog = document.createElement('dialog');
    dialog.className = 'image-zoom';
    dialog.setAttribute('aria-label', thumbnail.alt);
    const image = document.createElement('img');
    image.src = link.href;
    image.alt = thumbnail.alt;
    const close = document.createElement('button');
    close.type = 'button';
    close.textContent = 'Close';
    close.addEventListener('click', () => dialog.close());
    dialog.append(image, close);
    document.body.append(dialog);
    dialog.addEventListener('click', (click) => {
      const bounds = dialog.getBoundingClientRect();
      if (click.clientX < bounds.left || click.clientX > bounds.right ||
          click.clientY < bounds.top || click.clientY > bounds.bottom) dialog.close();
    });
    dialog.addEventListener('close', () => {
      dialog.remove();
      dialog = undefined;
      link.focus({preventScroll: true});
    }, {once: true});
    dialog.showModal();
  }, true);

  // Keep presentation shortcuts from navigating the slide behind the modal.
  window.addEventListener('keydown', (event) => {
    if (!dialog?.open) return;
    event.stopImmediatePropagation();
    if (event.key === 'Escape') {
      event.preventDefault();
      dialog.close();
    }
  }, true);
  window.addEventListener('hashchange', () => {
    if (dialog?.open) dialog.close();
  });
})();
