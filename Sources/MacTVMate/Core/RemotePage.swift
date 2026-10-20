/// The iPhone remote page (served by WebRemote). Self-contained HTML/CSS/JS, no external resources.
enum RemotePage {
    static let manifest = #"""
    {"name":"MacTVMate Remote","short_name":"MacTVMate","display":"standalone","background_color":"#111317",
     "theme_color":"#111317","icons":[{"src":"icon.png","sizes":"512x512","type":"image/png"}]}
    """#

    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="MacTVMate">
    <meta name="theme-color" content="#111317">
    <link rel="apple-touch-icon" href="icon.png">
    <link rel="manifest" href="manifest.json">
    <title>MacTVMate Remote</title>
    <style>
      :root { --bg:#111317; --panel:#1c1f26; --btn:#262a33; --btn2:#2f3440; --text:#f2f4f8; --dim:#9aa3b2; --faint:#5d6574;
              --accent:#2196f3; --live:#ef4444; }
      * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; -webkit-user-select:none; user-select:none; }
      html,body { margin:0; background:var(--bg); color:var(--text); font:15px -apple-system,BlinkMacSystemFont,sans-serif;
                  touch-action:manipulation; overscroll-behavior:none; }
      body { padding:calc(env(safe-area-inset-top) + 10px) 16px calc(env(safe-area-inset-bottom) + 76px); }
      /* Now playing */
      .np { display:flex; gap:12px; align-items:center; background:var(--panel); border-radius:16px; padding:10px; min-height:76px; }
      .np img { width:96px; height:60px; object-fit:cover; border-radius:10px; background:#000; flex:none; }
      .np .logo { object-fit:contain; padding:6px; }
      .np .t { min-width:0; flex:1; }
      .np .ch { color:var(--dim); font-size:12px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .np .title { font-weight:650; font-size:16px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin:2px 0; }
      .np .detail { font-size:12px; color:var(--accent); font-weight:600; }
      .bar { height:3px; background:#333a46; border-radius:2px; margin-top:6px; overflow:hidden; }
      .bar i { display:block; height:100%; background:var(--accent); width:0; }
      .live { color:var(--live); }
      /* Remote */
      .row { display:flex; justify-content:space-between; align-items:center; gap:12px; margin:16px 0; }
      .b { border:0; background:var(--btn); color:var(--text); border-radius:999px; font:inherit; display:flex;
           align-items:center; justify-content:center; flex-direction:column; gap:2px; }
      .b:active, .b.on { background:var(--btn2); transform:scale(.96); }
      .sm { width:64px; height:64px; font-size:22px; }
      .sm small, .tool small { font-size:10px; color:var(--dim); }
      .pad { position:relative; width:min(78vw,300px); height:min(78vw,300px); margin:6px auto 4px; border-radius:50%;
             background:radial-gradient(circle at 50% 40%, #2b303a, #1f232b); box-shadow:0 10px 30px #0008; }
      .pad button { position:absolute; border:0; background:transparent; color:var(--text); font-size:26px; }
      .pad .u { top:0; left:30%; width:40%; height:30%; } .pad .d { bottom:0; left:30%; width:40%; height:30%; }
      .pad .l { left:0; top:30%; width:30%; height:40%; } .pad .r { right:0; top:30%; width:30%; height:40%; }
      .pad button:active { color:var(--accent); }
      .pad .ok { left:31%; top:31%; width:38%; height:38%; border-radius:50%; background:var(--btn2); font-size:17px; font-weight:700;
                 box-shadow:inset 0 2px 6px #0006; }
      .pad .ok:active { background:var(--accent); color:#fff; }
      .rocker { width:64px; height:150px; border-radius:32px; background:var(--btn); display:flex; flex-direction:column; overflow:hidden; }
      .rocker button { flex:1; border:0; background:transparent; color:var(--text); font-size:24px; }
      .rocker button:active { background:var(--btn2); }
      .rocker span { font-size:11px; color:var(--dim); text-align:center; }
      .mid { display:flex; flex-direction:column; gap:12px; align-items:center; }
      .play { width:86px; height:86px; font-size:30px; background:var(--accent); }
      .play:active { background:#1976d2; }
      .tools { display:grid; grid-template-columns:repeat(5,1fr); gap:8px; margin-top:6px; }
      .tool { height:58px; border-radius:14px; font-size:18px; }
      .rec.on { color:var(--live); }
      /* Lists */
      .view { display:none; } .view.show { display:block; }
      select, input[type=search] { width:100%; font:inherit; font-size:16px; padding:12px 14px; border-radius:12px; border:0;
                                   background:var(--panel); color:var(--text); margin:14px 0 8px; -webkit-appearance:none; }
      .item { display:flex; gap:12px; align-items:center; padding:10px 6px; border-bottom:1px solid #1f232b; }
      .item:active { background:var(--panel); }
      .item img { width:52px; height:34px; object-fit:contain; flex:none; }
      .item .n { color:var(--faint); font-size:12px; width:34px; text-align:right; flex:none; font-variant-numeric:tabular-nums; }
      .item .t { min-width:0; flex:1; }
      .item .nm { font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .item .pg { color:var(--dim); font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .item .sc { color:var(--accent); font-size:12px; font-weight:600; }
      .item.cur .nm { color:var(--accent); }
      h3 { margin:16px 4px 4px; font-size:12px; color:var(--faint); text-transform:uppercase; letter-spacing:.06em; }
      .keys { display:grid; grid-template-columns:repeat(3,1fr); gap:12px; margin:20px auto; max-width:320px; }
      .keys button { height:72px; border-radius:20px; font-size:28px; }
      .entry { text-align:center; font-size:40px; font-weight:700; min-height:52px; margin-top:18px; font-variant-numeric:tabular-nums; }
      /* Tab bar */
      nav { position:fixed; left:0; right:0; bottom:0; display:flex; background:#16191ff2; backdrop-filter:blur(20px);
            -webkit-backdrop-filter:blur(20px); padding:6px 8px calc(env(safe-area-inset-bottom) + 6px); border-top:1px solid #222731; }
      nav button { flex:1; border:0; background:transparent; color:var(--faint); font:inherit; font-size:11px; display:flex;
                   flex-direction:column; align-items:center; gap:2px; padding:6px 0; }
      nav button b { font-size:20px; font-weight:400; }
      nav button.sel { color:var(--accent); }
      .err { text-align:center; color:var(--dim); margin-top:30vh; }
    </style>
    </head>
    <body>
    <div class="np" id="np"><img id="npimg" alt=""><div class="t"><div class="ch" id="npch">Connecting to MacTVMate…</div>
      <div class="title" id="nptitle"></div><div class="detail" id="npdetail"></div><div class="bar"><i id="npbar"></i></div></div></div>

    <section class="view show" id="v-remote">
      <div class="row">
        <button class="b sm" data-a="back">↩<small>Back</small></button>
        <button class="b sm" data-a="home">⌂<small>Guide</small></button>
        <button class="b sm" data-a="menu">≡<small>Menu</small></button>
      </div>
      <div class="pad">
        <button class="u" data-a="up" data-repeat>▲</button>
        <button class="l" data-a="left" data-repeat>◀</button>
        <button class="ok" data-a="ok">OK</button>
        <button class="r" data-a="right" data-repeat>▶</button>
        <button class="d" data-a="down" data-repeat>▼</button>
      </div>
      <div class="row">
        <div class="rocker"><button data-a="chUp" data-repeat>＋</button><span>CH</span><button data-a="chDown" data-repeat>－</button></div>
        <div class="mid">
          <button class="b play" data-a="playPause" id="pp">⏯</button>
          <button class="b sm" data-a="mute" id="mute">🔇<small>Mute</small></button>
        </div>
        <div class="rocker"><button data-a="volUp" data-repeat>＋</button><span>VOL</span><button data-a="volDown" data-repeat>－</button></div>
      </div>
      <div class="tools">
        <button class="b tool" data-a="seekBack">⏪<small>-30s</small></button>
        <button class="b tool" data-a="last">⇄<small>Last</small></button>
        <button class="b tool" data-a="info">ⓘ<small>Info</small></button>
        <button class="b tool rec" data-a="record" id="rec">⏺<small>Rec</small></button>
        <button class="b tool" data-a="seekFwd">⏩<small>+30s</small></button>
      </div>
      <div class="tools" style="grid-template-columns:1fr">
        <button class="b tool" data-a="fullscreen">⛶ <small>Full screen on the Mac</small></button>
      </div>
    </section>

    <section class="view" id="v-now">
      <select id="group"></select>
      <div id="chlist"></div>
    </section>

    <section class="view" id="v-search">
      <input type="search" id="q" placeholder="Search channels & programmes" autocomplete="off" autocorrect="off">
      <div id="results"></div>
    </section>

    <section class="view" id="v-keys">
      <div class="entry" id="entry"></div>
      <div class="keys">
        <button class="b" data-d="1">1</button><button class="b" data-d="2">2</button><button class="b" data-d="3">3</button>
        <button class="b" data-d="4">4</button><button class="b" data-d="5">5</button><button class="b" data-d="6">6</button>
        <button class="b" data-d="7">7</button><button class="b" data-d="8">8</button><button class="b" data-d="9">9</button>
        <button class="b" data-a="back">↩</button><button class="b" data-d="0">0</button><button class="b" data-a="ok">OK</button>
      </div>
    </section>

    <nav>
      <button data-v="remote" class="sel"><b>◎</b>Remote</button>
      <button data-v="now"><b>☰</b>On now</button>
      <button data-v="search"><b>⌕</b>Search</button>
      <button data-v="keys"><b>#</b>Number</button>
    </nav>

    <script>
    const params = new URLSearchParams(location.search);
    let KEY = params.get('k') || localStorage.getItem('mactvmate-key') || '';
    if (params.get('k')) localStorage.setItem('mactvmate-key', KEY);
    const $ = s => document.querySelector(s);
    const esc = s => (s ?? '').toString().replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

    async function api(path, body) {
      const r = await fetch(path, { method: body ? 'POST' : 'GET', cache: 'no-store',
        headers: { 'X-Remote-Key': KEY, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
      if (!r.ok) throw new Error(r.status);
      return r.json();
    }
    async function act(a, value) { try { render(await api('/api/key', { action: a, value })); } catch (e) { offline(); } }

    // Buttons (hold to repeat for arrows / rockers)
    document.querySelectorAll('[data-a]').forEach(btn => {
      let timer, rep;
      const start = e => { e.preventDefault(); act(btn.dataset.a);
        if (btn.hasAttribute('data-repeat')) timer = setTimeout(() => rep = setInterval(() => act(btn.dataset.a), 140), 420); };
      const stop = () => { clearTimeout(timer); clearInterval(rep); };
      btn.addEventListener('pointerdown', start);
      ['pointerup','pointerleave','pointercancel'].forEach(t => btn.addEventListener(t, stop));
    });

    // Tabs
    document.querySelectorAll('nav button').forEach(b => b.addEventListener('click', () => {
      document.querySelectorAll('nav button').forEach(x => x.classList.toggle('sel', x === b));
      document.querySelectorAll('.view').forEach(v => v.classList.toggle('show', v.id === 'v-' + b.dataset.v));
      if (b.dataset.v === 'now') loadChannels();
      if (b.dataset.v === 'search') setTimeout(() => $('#q').focus(), 50);
    }));

    // Now playing
    function render(s) {
      const p = s.playing;
      $('#mute').classList.toggle('on', !!s.muted);
      $('#rec').classList.toggle('on', !!s.recording);
      if (!p) { $('#npch').textContent = 'Nothing playing'; $('#nptitle').textContent = ''; $('#npdetail').textContent = '';
                $('#npimg').removeAttribute('src'); return; }
      $('#npch').innerHTML = (p.number ? esc(p.number) + '  ' : '') + esc(p.channel) + (p.live ? ' · <span class="live">LIVE</span>' : '');
      $('#nptitle').textContent = p.title || '';
      $('#npdetail').textContent = [p.score, p.detail, p.time].filter(Boolean).join(' · ');
      const img = p.art || p.logo;
      const el = $('#npimg');
      if (img && el.getAttribute('src') !== img) { el.src = img; el.className = p.art ? '' : 'logo'; }
      const frac = p.live ? (p.progress || 0) : (p.duration ? p.position / p.duration : 0);
      $('#npbar').style.width = Math.round(frac * 100) + '%';
      $('#pp').textContent = p.paused ? '▶' : '⏸';
    }
    function offline() { $('#npch').textContent = 'Can’t reach MacTVMate — is it open on the Mac?'; }
    async function poll() { if (document.hidden) return; try { render(await api('/api/state')); } catch (e) { offline(); } }
    setInterval(poll, 2500); poll();
    document.addEventListener('visibilitychange', poll);

    // On now
    function itemHTML(c, sub) {
      return `<div class="item ${c.playing ? 'cur' : ''}" data-id="${esc(c.id)}">
        <span class="n">${esc(c.number)}</span>${c.logo ? `<img src="${esc(c.logo)}" alt="">` : '<img alt="">'}
        <div class="t"><div class="nm">${esc(c.name)}</div><div class="pg">${esc(sub ?? c.title ?? '')}</div>
        ${c.score ? `<div class="sc">${esc(c.score)}</div>` : ''}</div></div>`;
    }
    function bindPlay(root) { root.querySelectorAll('.item').forEach(el => el.addEventListener('click', async () => {
      try { render(await api('/api/play', { id: el.dataset.id })); } catch (e) { offline(); } })); }
    async function loadGroups() {
      try {
        const g = await api('/api/groups');
        const saved = localStorage.getItem('mactvmate-group');
        $('#group').innerHTML = g.map(x => `<option ${x.name === saved ? 'selected' : ''}>${esc(x.name)}</option>`).join('');
      } catch (e) {}
    }
    async function loadChannels() {
      if (!$('#group').options.length) await loadGroups();
      const group = $('#group').value;
      localStorage.setItem('mactvmate-group', group);
      try {
        const r = await api('/api/channels?group=' + encodeURIComponent(group));
        $('#chlist').innerHTML = r.channels.map(c => itemHTML(c, c.title ? `${c.title} · ${c.time}` : '')).join('') ||
          '<p class="err" style="margin-top:20px">No channels</p>';
        bindPlay($('#chlist'));
      } catch (e) { offline(); }
    }
    $('#group').addEventListener('change', loadChannels);

    // Search
    let st;
    $('#q').addEventListener('input', () => { clearTimeout(st); st = setTimeout(doSearch, 250); });
    async function doSearch() {
      const q = $('#q').value.trim();
      if (!q) { $('#results').innerHTML = ''; return; }
      try {
        const r = await api('/api/search?q=' + encodeURIComponent(q));
        let h = '';
        if (r.channels.length) h += '<h3>Channels</h3>' + r.channels.map(c => itemHTML(c)).join('');
        if (r.programmes.length) h += '<h3>Programmes</h3>' + r.programmes.map(c => itemHTML(c, `${c.live ? 'LIVE · ' : ''}${c.title} · ${c.time}`)).join('');
        $('#results').innerHTML = h || '<p class="err" style="margin-top:20px">No matches</p>';
        bindPlay($('#results'));
      } catch (e) { offline(); }
    }

    // Number pad (MacTVMate jumps after a short pause, like a TV remote)
    let entry = '', et;
    document.querySelectorAll('[data-d]').forEach(b => b.addEventListener('pointerdown', e => {
      e.preventDefault(); entry += b.dataset.d; $('#entry').textContent = entry; act('digit', +b.dataset.d);
      clearTimeout(et); et = setTimeout(() => { entry = ''; $('#entry').textContent = ''; }, 1600);
    }));
    </script>
    </body>
    </html>
    """#
}
