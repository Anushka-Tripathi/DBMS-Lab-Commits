// Theme toggle (saved in the browser), dismissable messages, "mark all" buttons.
(function () {
  var root = document.documentElement;
  var toggle = document.getElementById('theme-toggle');
  if (toggle) toggle.addEventListener('click', function () {
    var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('theme', next); } catch (e) {}
  });
  document.querySelectorAll('.flash').forEach(function (el) {
    var btn = el.querySelector('.x');
    if (btn) btn.addEventListener('click', function () { el.remove(); });
    if (el.classList.contains('success')) setTimeout(function () { el.remove(); }, 6000);
  });
  document.querySelectorAll('[data-all]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      document.querySelectorAll('input[type=radio][value="' + btn.dataset.all + '"]').forEach(function (r) { r.checked = true; });
    });
  });
})();
