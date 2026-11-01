// Sanctuary Visual: page behaviour. Plain JS, no dependencies.
(() => {
  'use strict';

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const html = document.documentElement;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const saveData = navigator.connection?.saveData === true;
  const autoplay = !reduceMotion && !saveData;
  const behavior = reduceMotion ? 'auto' : 'smooth';
  const AV1 = 'video/mp4; codecs="av01.0.08M.08"';
  const pad = n => String(n).padStart(2, '0');
  const tryPlay = video => video.play().catch(() => {});

  // Adds AV1 + H.264 sources the first time a video is needed. The browser picks the first it can decode.
  function loadVideo(video, av1, h264 = av1.replace('.av1', '')) {
    if (video.dataset.loaded) return;
    video.dataset.loaded = 'true';
    for (const [src, type] of [[av1, AV1], [h264, 'video/mp4']]) {
      const source = document.createElement('source');
      source.src = src;
      source.type = type;
      video.append(source);
    }
    video.preload = 'auto';
    video.load();
  }

  // ---------- header: solid after the hero, hides while scrolling down ----------

  const header = $('[data-header]');
  const hero = $('.hero');
  let lastY = scrollY;
  let ticking = false;

  function onScroll() {
    const y = scrollY;
    header.classList.toggle('is-solid', y > hero.offsetHeight - header.offsetHeight);
    if (Math.abs(y - lastY) > 6) {
      header.classList.toggle('is-hidden', y > lastY && y > innerHeight * 0.5);
      lastY = y;
    }
    ticking = false;
  }
  addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  header.addEventListener('focusin', () => header.classList.remove('is-hidden'));
  onScroll();

  // ---------- menu ----------

  const menuToggle = $('[data-menu-toggle]');
  const menu = $('[data-menu]');
  const behindMenu = [$('main'), $('footer')];

  function setMenu(open) {
    html.classList.toggle('menu-open', open);
    menuToggle.setAttribute('aria-expanded', open);
    menuToggle.setAttribute('aria-label', open ? 'Close menu' : 'Menu');
    behindMenu.forEach(el => { el.inert = open; });
    if (open) $('a', menu).focus({ preventScroll: true });
  }
  menuToggle.addEventListener('click', () => setMenu(!html.classList.contains('menu-open')));
  menu.addEventListener('click', e => { if (e.target.closest('a')) setMenu(false); });
  addEventListener('keydown', e => {
    if (e.key === 'Escape' && html.classList.contains('menu-open')) {
      setMenu(false);
      menuToggle.focus();
    }
  });

  // ---------- hero video ----------

  const heroVideo = $('[data-hero]');
  const heroToggle = $('[data-hero-toggle]');

  if (heroVideo && autoplay) {
    const variant = matchMedia('(max-aspect-ratio: 3/4)').matches ? 'portrait'
      : innerWidth * devicePixelRatio > 1400 ? '1080' : '720';
    let userPaused = false;

    heroVideo.muted = true;
    loadVideo(heroVideo, `${heroVideo.dataset.src}-${variant}.av1.mp4`);
    heroVideo.addEventListener('playing', () => {
      heroVideo.classList.add('is-playing');
      heroToggle.hidden = false;
    });
    heroToggle.addEventListener('click', () => {
      userPaused = !heroVideo.paused;
      if (userPaused) heroVideo.pause(); else tryPlay(heroVideo);
      heroToggle.setAttribute('aria-pressed', userPaused);
    });
    // Stop decoding while the hero is off screen.
    new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) heroVideo.pause();
      else if (!userPaused) tryPlay(heroVideo);
    }).observe(heroVideo);
  }

  // ---------- social reels: play muted while on screen, tap for sound ----------

  const reels = $$('[data-reel]');

  function setSound(reel, on) {
    $('video', reel).muted = !on;
    $('.reel__btn', reel).setAttribute('aria-pressed', on);
  }

  for (const reel of reels) {
    const video = $('video', reel);
    video.muted = true;
    video.addEventListener('playing', () => reel.classList.add('is-ready'), { once: true });
    $('.reel__btn', reel).addEventListener('click', () => {
      const on = video.muted || video.paused;
      reels.forEach(r => { if (r !== reel) setSound(r, false); });
      loadVideo(video, `${video.dataset.src}.av1.mp4`);
      setSound(reel, on);
      if (on) tryPlay(video);
      else if (!autoplay) video.pause();
    });
  }

  const reelObserver = new IntersectionObserver(entries => {
    for (const { target, isIntersecting, intersectionRatio } of entries) {
      const video = $('video', target);
      if (isIntersecting && autoplay) loadVideo(video, `${video.dataset.src}.av1.mp4`);
      if (intersectionRatio >= 0.6) {
        if (autoplay || !video.muted) tryPlay(video);
      } else {
        video.pause();
        setSound(target, false);
      }
    }
  }, { threshold: [0, 0.6] });
  reels.forEach(reel => reelObserver.observe(reel));

  // ---------- film: loads only when someone presses play ----------

  const film = $('[data-film]');
  if (film) {
    const video = $('video', film);
    $('[data-film-play]', film).addEventListener('click', e => {
      e.preventDefault();
      const base = video.dataset.src;
      const large = innerWidth * devicePixelRatio > 1400;
      loadVideo(video, `${base}-1080.av1.mp4`, `${base}-${large ? 1080 : 720}.mp4`);
      reels.forEach(r => setSound(r, false));
      film.classList.add('is-active');
      video.focus({ preventScroll: true });
      tryPlay(video);
    });
  }

  // ---------- stills carousel ----------

  const track = $('[data-track]');
  const slides = $$('.slide', track);
  const prevBtn = $('[data-prev]');
  const nextBtn = $('[data-next]');
  const currentEl = $('[data-current]');
  let index = 0;

  $('[data-total]').textContent = pad(slides.length);

  function goTo(i, how = behavior) {
    i = Math.max(0, Math.min(slides.length - 1, i));
    track.scrollTo({ left: slides[i].offsetLeft - slides[0].offsetLeft, behavior: how });
  }

  function syncCarousel() {
    const stride = slides[1].offsetLeft - slides[0].offsetLeft || 1;
    // Before the lazy images are sized there is nothing to scroll, which must not read as "at the end".
    const scrollable = track.scrollWidth > track.clientWidth + 4;
    const atEnd = scrollable && track.scrollLeft >= track.scrollWidth - track.clientWidth - 4;
    index = atEnd ? slides.length - 1 : Math.round(track.scrollLeft / stride);
    currentEl.textContent = pad(index + 1);
    prevBtn.disabled = track.scrollLeft <= 4;
    nextBtn.disabled = atEnd;
  }

  let carouselTick = false;
  track.addEventListener('scroll', () => {
    if (!carouselTick) {
      carouselTick = true;
      requestAnimationFrame(() => { syncCarousel(); carouselTick = false; });
    }
  }, { passive: true });
  // Slide widths follow the images, so re-sync whenever they get their size.
  const slideObserver = new ResizeObserver(syncCarousel);
  slides.forEach(slide => slideObserver.observe(slide));
  slideObserver.observe(track);
  prevBtn.addEventListener('click', () => goTo(index - 1));
  nextBtn.addEventListener('click', () => goTo(index + 1));
  syncCarousel();

  // ---------- mouse drag paging (touch already scrolls natively) ----------

  // Drag a snap track with a mouse. On release, page one step in the drag direction.
  function dragPaging(el, { stride, current, goTo }) {
    let startX = 0, startLeft = 0, startIndex = 0, dragging = false, moved = false;

    el.addEventListener('pointerdown', e => {
      if (e.pointerType !== 'mouse' || e.button !== 0) return;
      startX = e.clientX;
      startLeft = el.scrollLeft;
      startIndex = current();
      dragging = true;
      moved = false;
    });
    el.addEventListener('pointermove', e => {
      if (!dragging) return;
      const dx = e.clientX - startX;
      if (!moved && Math.abs(dx) < 6) return;
      if (!moved) {
        moved = true;
        el.setPointerCapture(e.pointerId);
        el.classList.add('is-dragging');
      }
      el.scrollLeft = startLeft - dx;
    });
    const end = e => {
      if (!dragging) return;
      dragging = false;
      if (!moved) return;
      el.classList.remove('is-dragging');
      const dx = e.clientX - startX;
      const threshold = Math.min(80, stride() / 6);
      goTo(startIndex + (dx < -threshold ? 1 : dx > threshold ? -1 : 0));
    };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    // A drag must not count as a click (it would open the lightbox or close it).
    el.addEventListener('click', e => {
      if (!moved) return;
      e.stopPropagation();
      e.preventDefault();
      moved = false;
    }, true);
    el.addEventListener('dragstart', e => e.preventDefault());
  }

  dragPaging(track, {
    stride: () => slides[1].offsetLeft - slides[0].offsetLeft,
    current: () => index,
    goTo,
  });

  // ---------- lightbox: full-screen, swipeable copy of the stills ----------

  const lightbox = $('[data-lightbox]');
  const lbTrack = $('[data-lb-track]', lightbox);
  const lbCurrent = $('[data-lb-current]', lightbox);
  let lbIndex = 0;

  $('[data-lb-total]', lightbox).textContent = pad(slides.length);

  function buildLightbox() {
    for (const slide of slides) {
      const item = document.createElement('li');
      const picture = $('picture', slide).cloneNode(true);
      $$('source', picture).forEach(s => { s.sizes = '(max-aspect-ratio: 4/3) 100vw, 133vh'; });
      item.append(picture);
      lbTrack.append(item);
    }
  }

  function syncLightbox() {
    lbIndex = Math.round(lbTrack.scrollLeft / lbTrack.clientWidth);
    lbCurrent.textContent = pad(lbIndex + 1);
  }

  const lbStep = dir => lbTrack.scrollTo({
    left: Math.max(0, Math.min(slides.length - 1, lbIndex + dir)) * lbTrack.clientWidth,
    behavior,
  });

  dragPaging(lbTrack, {
    stride: () => lbTrack.clientWidth,
    current: () => lbIndex,
    goTo: i => lbTrack.scrollTo({ left: Math.max(0, Math.min(slides.length - 1, i)) * lbTrack.clientWidth, behavior }),
  });

  function openLightbox(i) {
    if (!lbTrack.children.length) buildLightbox();
    html.classList.add('lb-open');
    lightbox.showModal();
    lbTrack.scrollTo({ left: i * lbTrack.clientWidth, behavior: 'auto' });
    syncLightbox();
  }

  track.addEventListener('click', e => {
    const btn = e.target.closest('[data-open]');
    if (btn) openLightbox(Number(btn.dataset.open));
  });
  lbTrack.addEventListener('scroll', () => requestAnimationFrame(syncLightbox), { passive: true });
  lbTrack.addEventListener('click', e => { if (e.target.tagName !== 'IMG') lightbox.close(); });
  $('[data-lb-close]', lightbox).addEventListener('click', () => lightbox.close());
  $('[data-lb-prev]', lightbox).addEventListener('click', () => lbStep(-1));
  $('[data-lb-next]', lightbox).addEventListener('click', () => lbStep(1));
  lightbox.addEventListener('keydown', e => {
    if (e.key === 'ArrowRight') { e.preventDefault(); lbStep(1); }
    if (e.key === 'ArrowLeft') { e.preventDefault(); lbStep(-1); }
  });
  lightbox.addEventListener('close', () => {
    html.classList.remove('lb-open');
    goTo(lbIndex, 'auto');
    $('button', slides[lbIndex]).focus({ preventScroll: true });
  });

  // ---------- contact form ----------

  const form = $('[data-form]');
  if (form) {
    const status = $('[data-form-status]', form);
    const submit = $('[type="submit"]', form);
    form.addEventListener('submit', async e => {
      e.preventDefault();
      submit.disabled = true;
      status.className = 'form__status';
      status.textContent = 'Sending…';
      try {
        const res = await fetch(form.action, {
          method: 'POST',
          body: new FormData(form),
          headers: { Accept: 'application/json' },
        });
        if (!res.ok) throw new Error(res.status);
        form.reset();
        status.textContent = "Thanks, we've got your enquiry and will be in touch soon.";
      } catch {
        status.classList.add('is-error');
        status.textContent = 'Something went wrong. Please try again or email us directly.';
      }
      submit.disabled = false;
    });
  }

  // ---------- reveal on scroll ----------

  const revealObserver = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-in');
        revealObserver.unobserve(entry.target);
      }
    }
  }, { rootMargin: '0px 0px -8% 0px' });
  $$('[data-reveal]').forEach(el => revealObserver.observe(el));

  $$('[data-year]').forEach(el => { el.textContent = new Date().getFullYear(); });
})();
