(function () {
  var data = JSON.parse(document.getElementById('refdata').textContent);
  var modSel = document.getElementById('refmod'), kindSel = document.getElementById('refkind'), q = document.getElementById('refq');
  var list = document.getElementById('reflist'), count = document.getElementById('refcount'), more = document.getElementById('refmore');
  var PAGE = 150, shown = PAGE, matches = [];
  var mods = Object.keys(data);
  modSel.innerHTML = '<option value="*">All modules</option>' + mods.map(function (m) { return '<option>' + m + '</option>'; }).join('');
  var kinds = {}; mods.forEach(function (m) { data[m].forEach(function (e) { kinds[e[0]] = 1; }); });
  kindSel.innerHTML = '<option value="*">All types</option>' + Object.keys(kinds).sort().map(function (k) { return '<option>' + k + '</option>'; }).join('');
  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function run() {
    var m = modSel.value, k = kindSel.value, term = q.value.trim().toLowerCase();
    matches = [];
    (m === '*' ? mods : [m]).forEach(function (mm) {
      data[mm].forEach(function (e) {
        if (k !== '*' && e[0] !== k) return;
        if (term && (e[1] + '\n' + e[2]).toLowerCase().indexOf(term) < 0) return;
        matches.push([mm, e]);
      });
    });
    shown = PAGE; render();
  }
  function render() {
    count.textContent = matches.length + ' element' + (matches.length === 1 ? '' : 's');
    list.innerHTML = matches.slice(0, shown).map(function (x) {
      var e = x[1];
      return '<details><summary><span class="k">' + esc(e[0]) + '</span>' + esc(x[0]) + ' / ' + esc(e[1]) + '</summary><pre>' + esc(e[2] || '(no body)') + '</pre></details>';
    }).join('');
    more.hidden = matches.length <= shown;
  }
  more.addEventListener('click', function () { shown += PAGE; render(); });
  var t; q.addEventListener('input', function () { clearTimeout(t); t = setTimeout(run, 150); });
  modSel.addEventListener('change', run); kindSel.addEventListener('change', run);
  run();
})();
