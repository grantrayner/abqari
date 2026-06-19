// Initialises the Pagefind UI inside #abqari-search. The pagefind-ui.js
// runtime is loaded earlier in the document, so PagefindUI is defined by
// the time this runs. Loaded with `defer` so it executes after parsing.
window.addEventListener('DOMContentLoaded', function () {
  if (typeof PagefindUI === 'undefined') return;
  new PagefindUI({
    element: '#abqari-search',
    showSubResults: true,
    showImages: false
  });
});
