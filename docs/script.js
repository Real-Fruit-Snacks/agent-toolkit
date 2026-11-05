// agent-toolkit page: theme switch, copy buttons, platform tabs, and the load plan's readout.
// The plan's animation is CSS; this only narrates it and reads out the column under the pointer or
// the arrow keys. Without JS the plan still animates and the readout shows the final line.
(function () {
  var root = document.documentElement;
  var still = matchMedia('(prefers-reduced-motion: reduce)');
  var light = matchMedia('(prefers-color-scheme: light)');
  var $ = function (id) { return document.getElementById(id); };

  // ---- theme ----
  function theme() { return root.dataset.theme || (light.matches ? 'dayshift' : 'nightshift'); }
  function paint() {
    var night = theme() === 'nightshift';
    document.querySelector('meta[name="theme-color"]').content = night ? '#0C0D10' : '#F6F5F2';
    $('theme').setAttribute('aria-label', 'Theme: ' + (night ? 'night' : 'day') + '. Switch to ' + (night ? 'day' : 'night'));
  }
  $('theme').addEventListener('click', function () {
    root.dataset.theme = theme() === 'nightshift' ? 'dayshift' : 'nightshift';
    try { localStorage.setItem('rfs-theme', root.dataset.theme); } catch (e) {}
    paint();
  });
  light.addEventListener('change', paint);
  paint();

  // ---- copy ----
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      var done = function (ok) { b.textContent = ok ? 'Copied' : 'Select it'; clearTimeout(b._t); b._t = setTimeout(function () { b.textContent = 'Copy'; }, 1600); };
      if (navigator.clipboard) navigator.clipboard.writeText(b.dataset.copy).then(function () { done(true); }, function () { done(false); });
      else done(false);
    });
  });

  // ---- platform tabs ----
  var tabs = [].slice.call(document.querySelectorAll('[role="tab"]'));
  function pick(t, focus) {
    tabs.forEach(function (x) {
      var on = x === t;
      x.setAttribute('aria-selected', on); x.tabIndex = on ? 0 : -1;
      $(x.getAttribute('aria-controls')).hidden = !on;
    });
    if (focus) t.focus();
  }
  tabs.forEach(function (t, i) {
    t.addEventListener('click', function () { pick(t); });
    t.addEventListener('keydown', function (e) {
      var k = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (k) { e.preventDefault(); pick(tabs[(i + k + tabs.length) % tabs.length], true); }
    });
  });
  if (tabs.length) pick(tabs[0]);

  // ---- the load plan ----
  var plan = $('plan'), out = $('readout'), foot = plan && plan.querySelector('.plan-foot');
  if (!plan || !out || !foot) return;
  var stage = plan.querySelector('.stage'), cols = [].slice.call(plan.querySelectorAll('.col'));
  var said = foot.dataset, timers = [], sel = -1;
  var esc = function (s) { return s.replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); };
  function say(html) { out.innerHTML = html; }
  function done() { say(esc(said.done).replace('is consistent', 'is <span class="ok">consistent</span>')); }
  function show(i) {
    cols.forEach(function (c, k) { c.classList.toggle('sel', k === i); });
    sel = i;
    if (i < 0) return done();
    var c = cols[i].dataset;
    say(esc(c.n) + '<br><span class="m">' + esc(c.s) + ' · sha256 ' + c.d + '… · ' + esc(c.to) + '</span>');
  }

  // narrate the CSS replay; the times match the animation delays in styles.css
  function narrate() {
    timers.forEach(clearTimeout); timers = [];
    if (still.matches) return done();
    var at = function (ms, fn) { timers.push(setTimeout(fn, ms)); };
    say(esc(said.pack));
    if (said.over) {
      at(1400, function () { say('<span class="bad">' + esc(said.over) + '</span>'); });
      at(2300, function () { say(esc(said.split)); });
    }
    var n = +said.count;
    for (var k = 1; k <= n; k++) (function (k) { at(3000 + k * 25, function () { say('verify-release.ps1: <span class="ok">' + k + '</span> of ' + n + ' digests match'); }); })(k);
    at(3000 + n * 25 + 250, done);
  }
  function replay() {
    show(-1);
    plan.classList.remove('run'); void plan.offsetWidth; plan.classList.add('run');
    narrate();
  }
  $('replay').addEventListener('click', replay);
  if (still.matches) $('replay').hidden = true;
  still.addEventListener('change', function () { $('replay').hidden = still.matches; });
  narrate();

  // read a column: pointer, tap, or the arrow keys once the plan has focus
  cols.forEach(function (c, i) {
    c.addEventListener('pointerenter', function () { timers.forEach(clearTimeout); show(i); });
    c.addEventListener('click', function () { timers.forEach(clearTimeout); show(i); });
  });
  stage.addEventListener('pointerleave', function () { if (sel >= 0 && document.activeElement !== stage) show(-1); });
  stage.tabIndex = 0;
  stage.setAttribute('role', 'group');
  stage.setAttribute('aria-label', 'Load plan, ' + cols.length + ' assets. Use the left and right arrow keys to read each one.');
  stage.addEventListener('keydown', function (e) {
    var k = { ArrowRight: 1, ArrowLeft: -1, Home: -Infinity, End: Infinity }[e.key];
    if (e.key === 'Escape') return show(-1);
    if (!k) return;
    e.preventDefault(); timers.forEach(clearTimeout);
    show(Math.max(0, Math.min(cols.length - 1, k === -Infinity ? 0 : k === Infinity ? cols.length - 1 : (sel < 0 ? 0 : sel + k))));
  });
  stage.addEventListener('blur', function () { show(-1); });
})();
