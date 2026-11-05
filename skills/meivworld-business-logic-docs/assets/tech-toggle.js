(function () {
  var btn = document.getElementById('techToggle');
  function set(on) {
    document.body.classList.toggle('show-tech', on);
    btn.setAttribute('aria-pressed', on ? 'true' : 'false');
    btn.textContent = on ? 'Hide technical names' : 'Show technical names';
  }
  try { set(localStorage.getItem('bl-tech') === '1'); } catch (e) {}
  btn.addEventListener('click', function () {
    var on = !document.body.classList.contains('show-tech');
    set(on);
    try { localStorage.setItem('bl-tech', on ? '1' : '0'); } catch (e) {}
  });
})();
