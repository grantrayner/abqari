// Vanilla-JS carousel for the _carousel partial. No Bootstrap dependency,
// no inline scripts — works under the strict 'self'-only CSP.
//
// Each `[data-carousel]` element has slides marked `.carousel__slide`
// (one with `.is-active` initially), prev/next buttons, and a position
// counter. Arrow keys also navigate when the carousel has focus.
(function () {
  document.querySelectorAll('[data-carousel]').forEach(initCarousel);

  function initCarousel(root) {
    var slides = Array.prototype.slice.call(root.querySelectorAll('.carousel__slide'));
    if (slides.length < 2) return;

    var counter = root.querySelector('[data-carousel-current]');
    var current = Math.max(0, slides.findIndex(function (s) { return s.classList.contains('is-active'); }));

    function show(index) {
      var next = (index + slides.length) % slides.length;
      slides[current].classList.remove('is-active');
      slides[current].setAttribute('aria-hidden', 'true');
      slides[next].classList.add('is-active');
      slides[next].setAttribute('aria-hidden', 'false');
      current = next;
      if (counter) counter.textContent = String(current + 1);
    }

    var prevBtn = root.querySelector('[data-carousel-prev]');
    var nextBtn = root.querySelector('[data-carousel-next]');
    if (prevBtn) prevBtn.addEventListener('click', function () { show(current - 1); });
    if (nextBtn) nextBtn.addEventListener('click', function () { show(current + 1); });

    // Keyboard navigation when the carousel (or anything inside) has focus.
    root.setAttribute('tabindex', '0');
    root.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowLeft')  { e.preventDefault(); show(current - 1); }
      if (e.key === 'ArrowRight') { e.preventDefault(); show(current + 1); }
    });
  }
})();
