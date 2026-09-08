// Freshness badge: reads updated.json (single source of truth),
// renders an auto-computed quarter label. Hides itself if fetch fails.
(function () {
  var badges = document.querySelectorAll('[data-freshness]');
  if (!badges.length) return;
  function label(d) {
    var q = Math.floor(d.getMonth() / 3) + 1;
    return 'Updated Q' + q + ' ' + d.getFullYear();
  }
  function apply(dateStr) {
    var d = dateStr ? new Date(dateStr + 'T00:00:00') : null;
    if (!d || isNaN(d.getTime())) { hide(); return; }
    var text = label(d);
    for (var i = 0; i < badges.length; i++) {
      badges[i].textContent = text;
      badges[i].removeAttribute('hidden');
    }
  }
  function hide() {
    for (var i = 0; i < badges.length; i++) badges[i].remove();
  }
  try {
    fetch('updated.json', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (j) { apply(j.lastUpdated); })
      .catch(hide);
  } catch (e) { hide(); }
})();
