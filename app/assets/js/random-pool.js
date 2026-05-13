/* random-pool.js — runtime randomness for static sites.
 *
 * Used by the "From the archive" (random_post) and "From the gallery"
 * (random_photo) home modules to pick a different card on each page
 * load. The server renders a small pool of candidates inside each
 * `[data-random-pool]` container, with all but the first marked
 * `hidden`. This script:
 *
 *   1. Picks one random child of each pool to reveal, hides the rest.
 *   2. Runs once on initial DOM ready.
 *   3. Re-runs on the `pageshow` event so back/forward cache restores
 *      also re-roll instead of showing the same card the user just
 *      saw.
 *
 * Progressive enhancement: with JS disabled, the first child of the
 * pool stays visible (the server-rendered fallback). No layout shift
 * — the pool's height is determined by the visible card, not the pool
 * itself, since hidden children take no space.
 */
(function () {
  function pick(pool) {
    var items = pool.children;
    if (items.length <= 1) return;
    var chosen = Math.floor(Math.random() * items.length);
    for (var i = 0; i < items.length; i++) {
      items[i].hidden = (i !== chosen);
    }
  }

  function refresh() {
    var pools = document.querySelectorAll('[data-random-pool]');
    for (var i = 0; i < pools.length; i++) pick(pools[i]);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', refresh);
  } else {
    refresh();
  }
  // `pageshow` fires on initial load AND on back/forward cache
  // restore — the latter is exactly when a static page would
  // otherwise show the same card the user just navigated away from.
  window.addEventListener('pageshow', refresh);
})();
