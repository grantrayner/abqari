// Click handler for the theme toggle. The bootstrap script in <head>
// already hydrated `data-theme` from localStorage before render to avoid
// a flash of the wrong theme; this script handles the user gesture and
// keeps the button's aria-pressed state in sync with the active theme.
//
// Loaded with `defer` so it attaches after parsing. The bootstrap is
// what prevents FOUC; this script handles state changes.
(function () {
  function isDark() {
    var t = document.documentElement.getAttribute('data-theme');
    if (t === 'dark') return true;
    if (t === 'light') return false;
    // No explicit choice yet — fall back to the system preference.
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function syncPressed() {
    var pressed = isDark() ? 'true' : 'false';
    document.querySelectorAll('[data-theme-toggle]').forEach(function (btn) {
      btn.setAttribute('aria-pressed', pressed);
    });
  }

  function flip() {
    var next = isDark() ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    try { localStorage.setItem('theme', next); } catch (e) {}
    syncPressed();
  }

  // Initial sync — the server-rendered HTML had aria-pressed="false" as a
  // default; correct it to match the resolved theme as soon as we run.
  syncPressed();

  document.addEventListener('click', function (e) {
    var trigger = e.target.closest('[data-theme-toggle]');
    if (trigger) flip();
  });
})();
