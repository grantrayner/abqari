// Click handler for the contact button. Reassembles the email address
// from data-user + data-domain attributes on click and opens the user's
// mail client via mailto:.
//
// Defence against email harvesters: the full address never appears as a
// single string in the page HTML, and the `mailto:` prefix isn't present
// either — both are constructed in memory after the user gestures, so a
// bot scraping static HTML can't reconstruct anything to spam.
//
// Loaded with `defer` from _contact_button.html.erb. Uses event delegation
// so a layout that renders multiple buttons still works with one handler.
(function () {
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.contact-button[data-user][data-domain]');
    if (!btn) return;
    e.preventDefault();
    var user = btn.dataset.user;
    var domain = btn.dataset.domain;
    if (user && domain) {
      var href = 'mailto:' + user + '@' + domain;
      var subject = btn.dataset.subject;
      if (subject) {
        href += '?subject=' + encodeURIComponent(subject);
      }
      window.location.href = href;
    }
  });
})();
