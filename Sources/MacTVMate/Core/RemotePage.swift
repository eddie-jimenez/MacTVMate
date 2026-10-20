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
      .entry { text-align:center; font-size:34px; color:var(--dim); font-weight:700; min-height:52px; margin-top:18px; font-variant-numeric:tabular-nums; }
      /* Section jump + chips */
      .goto { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin:14px 0 4px; }
      .goto button { height:44px; border-radius:12px; font-size:13px; flex-direction:row; gap:6px; }
      .goto button.on { background:var(--accent); color:#fff; }
      .label { font-size:11px; color:var(--faint); text-transform:uppercase; letter-spacing:.06em; margin:14px 4px 0; }
      .chips { display:flex; gap:8px; overflow-x:auto; padding:12px 0 6px; margin:0 -16px; padding-left:16px; padding-right:16px;
               scrollbar-width:none; -webkit-overflow-scrolling:touch; }
      .chips::-webkit-scrollbar { display:none; }
      #groups, #cats { position:sticky; top:0; z-index:2; background:var(--bg); padding-top:calc(env(safe-area-inset-top) + 8px); }
      .chip { flex:none; border:0; border-radius:999px; padding:9px 14px; background:var(--panel); color:var(--text); font:inherit;
              font-size:14px; white-space:nowrap; }
      .chip.sel { background:var(--accent); color:#fff; font-weight:600; }
      .chip small { color:inherit; opacity:.6; margin-left:4px; font-size:12px; }
      /* Poster grid */
      .grid { display:grid; grid-template-columns:repeat(3,1fr); gap:12px 10px; margin-top:8px; }
      .poster { position:relative; }
      .poster .img { aspect-ratio:2/3; border-radius:10px; background:var(--panel) center/cover no-repeat; }
      .poster .nm { font-size:12px; font-weight:600; margin-top:5px; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
      .poster .rt { position:absolute; left:5px; top:5px; background:#000c; color:#f5c518; font-size:10px; font-weight:700;
                    padding:2px 5px; border-radius:5px; }
      .poster .rs { position:absolute; right:5px; top:5px; background:var(--accent); color:#fff; font-size:10px; font-weight:700;
                    padding:2px 5px; border-radius:5px; }
      .more { width:100%; height:46px; border-radius:12px; margin:16px 0; }
      .empty { color:var(--dim); text-align:center; padding:30px 10px; }
      /* Sheet */
      .sheet { position:fixed; inset:0; background:#000a; display:none; z-index:10; }
      .sheet.show { display:block; }
      .sheet .card { position:absolute; left:0; right:0; bottom:0; max-height:86vh; overflow-y:auto; background:var(--bg);
                     border-radius:20px 20px 0 0; padding:18px 16px calc(env(safe-area-inset-bottom) + 18px); }
      .sheet .hd { display:flex; gap:14px; }
      .sheet .hd .img { width:96px; flex:none; aspect-ratio:2/3; border-radius:10px; background:var(--panel) center/cover no-repeat; }
      .sheet h2 { margin:0 0 6px; font-size:19px; }
      .sheet .sub { color:var(--dim); font-size:13px; }
      .sheet .plot { color:var(--dim); font-size:13px; margin-top:8px; display:-webkit-box; -webkit-line-clamp:5; -webkit-box-orient:vertical; overflow:hidden; }
      .sheet .acts { display:flex; gap:10px; margin:16px 0 6px; }
      .sheet .acts button { flex:1; height:48px; border-radius:12px; font-size:15px; flex-direction:row; gap:6px; }
      .sheet .primary { background:var(--accent); color:#fff; font-weight:600; }
      .sheet .x { position:absolute; right:12px; top:12px; width:34px; height:34px; font-size:16px; }
      .ep { display:flex; gap:10px; align-items:center; padding:12px 4px; border-bottom:1px solid #1f232b; }
      .ep:active { background:var(--panel); }
      .ep .no { color:var(--faint); width:26px; text-align:right; flex:none; font-variant-numeric:tabular-nums; }
      .ep .t { flex:1; min-width:0; } .ep .t div { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .ep .d { color:var(--faint); font-size:12px; }
      .ep .w { color:var(--accent); font-size:12px; }
      .np .gear { flex:none; width:40px; height:40px; border-radius:50%; font-size:20px; align-self:flex-start; }
      .item .go { flex:none; width:40px; height:40px; border-radius:50%; font-size:15px; }
      .rec.on { background:#3a1414; color:var(--live); }
      .hint { color:var(--faint); font-size:12px; text-align:center; margin:10px 8px 0; }
      .prog { display:flex; gap:10px; align-items:center; padding:11px 4px; border-bottom:1px solid #1f232b; }
      .prog.past { opacity:.55; }
      .prog .tm { width:66px; flex:none; color:var(--dim); font-size:12px; font-variant-numeric:tabular-nums; }
      .prog .t { flex:1; min-width:0; } .prog .t div { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .prog .t small { color:var(--dim); font-size:12px; }
      .prog .ic { flex:none; width:38px; height:38px; border-radius:50%; font-size:15px; }
      .prog .ic.on { background:var(--accent); color:#fff; }
      .prog .ic.rec.on { background:var(--live); }
      .day { margin:14px 4px 2px; font-size:12px; color:var(--faint); text-transform:uppercase; letter-spacing:.06em; }
      .badge { background:var(--live); color:#fff; font-size:10px; font-weight:700; padding:1px 5px; border-radius:4px; margin-right:4px; }
      .set { display:flex; align-items:center; gap:10px; padding:12px 4px; border-bottom:1px solid #1f232b; }
      .set span { flex:1; } .set select { width:auto; margin:0; padding:8px 10px; font-size:14px; }
      .sw { position:relative; width:50px; height:30px; flex:none; border-radius:15px; background:#3a404c; border:0; }
      .sw::after { content:''; position:absolute; top:3px; left:3px; width:24px; height:24px; border-radius:50%; background:#fff; transition:left .15s; }
      .sw.on { background:#34c759; } .sw.on::after { left:23px; }
      .sw:disabled { opacity:.4; }
      .swatches { display:flex; flex-wrap:wrap; gap:10px; padding:10px 4px; }
      .swatches button { width:34px; height:34px; border-radius:50%; border:3px solid transparent; }
      .swatches button.on { border-color:#fff; }
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
    <div class="np" id="np"><img id="npimg" alt=""><div class="t" id="npt"><div class="ch" id="npch">Connecting to MacTVMate…</div>
      <div class="title" id="nptitle"></div><div class="detail" id="npdetail"></div><div class="bar"><i id="npbar"></i></div></div>
      <button class="b gear" id="gear" aria-label="Settings">⚙︎</button></div>

    <section class="view show" id="v-remote">
      <div class="tools" style="grid-template-columns:repeat(4,1fr);margin-top:12px">
        <button class="b tool rec" data-a="record" id="rec">⏺<small id="reclabel">Record</small></button>
        <button class="b tool" id="favbtn">☆<small id="favlabel">Favourite</small></button>
        <button class="b tool" id="tracksbtn">🎧<small>Audio & subs</small></button>
        <button class="b tool" data-a="info">ⓘ<small>Info</small></button>
      </div>
      <div class="label">Show on the TV</div>
      <div class="goto">
        <button class="b" data-go="guide">📺 TV guide</button>
        <button class="b" data-go="movies">🎬 Movies</button>
        <button class="b" data-go="shows">🍿 Shows</button>
        <button class="b" data-go="recordings">⏺ Recordings</button>
        <button class="b" data-go="mylist">🔖 My list</button>
        <button class="b" data-go="settings">⚙︎ Settings</button>
      </div>
      <div class="row">
        <button class="b sm" data-a="back">↩<small>Back</small></button>
        <button class="b sm" data-a="home">⌂<small>Guide</small></button>
        <button class="b sm" data-a="menu">≡<small>Options</small></button>
      </div>
      <div class="pad">
        <button class="u" data-a="up" data-repeat>▲</button>
        <button class="l" data-a="left" data-repeat>◀</button>
        <button class="ok" data-a="ok" data-hold="longOk">OK</button>
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
        <button class="b tool" data-a="fullscreen">⛶<small>Full screen</small></button>
        <button class="b tool" id="openkeys">#<small>Number</small></button>
        <button class="b tool" data-a="seekFwd">⏩<small>+30s</small></button>
      </div>
      <p class="hint">⏺ Record records what's playing now. To record a programme later, open the channel in the TV tab (or tap the now-playing card) and tap ⏺ next to it. Hold OK for the options of what's selected on the TV.</p>
    </section>

    <section class="view" id="v-tv">
      <div class="chips" id="groups"></div>
      <div id="chlist"></div>
    </section>

    <section class="view" id="v-vod">
      <div class="chips" id="cats"></div>
      <input type="search" id="vq" placeholder="Search movies" autocomplete="off" autocorrect="off">
      <div class="grid" id="vgrid"></div>
      <button class="b more" id="vmore" style="display:none">Load more</button>
    </section>

    <section class="view" id="v-library">
      <h3>Scheduled & recording</h3><div id="upcoming"></div>
      <h3>Recordings</h3><div id="recs"></div>
      <h3>Reminders</h3><div id="reminders"></div>
      <h3>Favourite channels</h3><div id="favs"></div>
      <h3>My list</h3><div class="grid" id="mylist"></div>
    </section>

    <section class="view" id="v-search">
      <input type="search" id="q" placeholder="Search channels & programmes" autocomplete="off" autocorrect="off">
      <div id="results"></div>
    </section>

    <section class="view" id="v-keys">
      <div class="entry" id="entry">Channel number</div>
      <div class="keys">
        <button class="b" data-d="1">1</button><button class="b" data-d="2">2</button><button class="b" data-d="3">3</button>
        <button class="b" data-d="4">4</button><button class="b" data-d="5">5</button><button class="b" data-d="6">6</button>
        <button class="b" data-d="7">7</button><button class="b" data-d="8">8</button><button class="b" data-d="9">9</button>
        <button class="b" data-a="back">↩</button><button class="b" data-d="0">0</button><button class="b" data-a="ok">OK</button>
      </div>
    </section>

    <div class="sheet" id="sheet"><div class="card" id="sheetcard"></div></div>

    <nav>
      <button data-v="remote" class="sel"><b>◎</b>Remote</button>
      <button data-v="tv"><b>📺</b>TV</button>
      <button data-v="movies"><b>🎬</b>Movies</button>
      <button data-v="shows"><b>🍿</b>Shows</button>
      <button data-v="library"><b>🔖</b>Library</button>
      <button data-v="search"><b>⌕</b>Search</button>
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
    document.querySelectorAll('[data-hold]').forEach(btn => {
      let timer, held = false;
      btn.addEventListener('pointerdown', e => { e.preventDefault(); held = false;
        timer = setTimeout(() => { held = true; act(btn.dataset.hold); navigator.vibrate?.(20); }, 550); });
      btn.addEventListener('pointerup', () => { clearTimeout(timer); if (!held) act(btn.dataset.a); });
      ['pointerleave','pointercancel'].forEach(t => btn.addEventListener(t, () => clearTimeout(timer)));
    });
    document.querySelectorAll('[data-a]:not([data-hold])').forEach(btn => {
      let timer, rep;
      const start = e => { e.preventDefault(); act(btn.dataset.a);
        if (btn.hasAttribute('data-repeat')) timer = setTimeout(() => rep = setInterval(() => act(btn.dataset.a), 140), 420); };
      const stop = () => { clearTimeout(timer); clearInterval(rep); };
      btn.addEventListener('pointerdown', start);
      ['pointerup','pointerleave','pointercancel'].forEach(t => btn.addEventListener(t, stop));
    });

    // Tabs (Movies and Shows share one view)
    function showView(v) {
      document.querySelectorAll('nav button').forEach(x => x.classList.toggle('sel', x.dataset.v === v));
      const id = (v === 'movies' || v === 'shows') ? 'vod' : v;
      document.querySelectorAll('.view').forEach(el => el.classList.toggle('show', el.id === 'v-' + id));
      if (v === 'tv') loadChannels();
      if (v === 'movies' || v === 'shows') openVOD(v === 'movies' ? 'movies' : 'series');
      if (v === 'library') loadLibrary();
      if (v === 'search') setTimeout(() => $('#q').focus(), 50);
      window.scrollTo(0, 0);
    }
    document.querySelectorAll('nav button').forEach(b => b.addEventListener('click', () => showView(b.dataset.v)));
    $('#openkeys').addEventListener('click', () => showView('keys'));

    // Show a section on the Mac
    document.querySelectorAll('[data-go]').forEach(b => b.addEventListener('click', async () => {
      try { render(await api('/api/go', { section: b.dataset.go })); } catch (e) { offline(); }
    }));
    const screenOf = { guide: 'guide', movies: 'movies', shows: 'shows', recordings: 'recordings', myList: 'mylist' };

    // Now playing
    function render(s) {
      const cur = s.screen === 'player' ? '' : screenOf[s.screen];
      document.querySelectorAll('[data-go]').forEach(b => b.classList.toggle('on', b.dataset.go === cur));
      const p = s.playing;
      $('#mute').classList.toggle('on', !!s.muted);
      $('#rec').classList.toggle('on', !!s.recording);
      $('#reclabel').textContent = s.recording ? '● Stop rec' : 'Record';
      state = s;
      const fav = !!(s.playing && s.playing.favourite);
      $('#favbtn').firstChild.textContent = fav ? '★' : '☆';
      $('#favlabel').textContent = fav ? 'Favourite ✓' : 'Favourite';
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
    let state = {};
    function offline() { $('#npch').textContent = 'Can’t reach MacTVMate — is it open on the Mac?'; }
    async function poll() { if (document.hidden) return; try { render(await api('/api/state')); } catch (e) { offline(); } }
    setInterval(poll, 2500); poll();
    document.addEventListener('visibilitychange', poll);

    // On now
    function itemHTML(c, sub) {
      return `<div class="item ${c.playing ? 'cur' : ''}" data-id="${esc(c.id)}">
        <span class="n">${esc(c.number)}</span>${c.logo ? `<img src="${esc(c.logo)}" alt="">` : '<img alt="">'}
        <div class="t"><div class="nm">${esc(c.name)}</div><div class="pg">${esc(sub ?? c.title ?? '')}</div>
        ${c.score ? `<div class="sc">${esc(c.score)}</div>` : ''}</div>
        <button class="b go" data-play="${esc(c.id)}" aria-label="Watch">▶</button></div>`;
    }
    // Row: open the channel (schedule, record, remind, favourite). ▶: watch straight away.
    function bindPlay(root) {
      root.querySelectorAll('.item[data-id]').forEach(el => el.addEventListener('click', e => {
        if (e.target.closest('[data-play]')) return;
        openChannel(el.dataset.id);
      }));
      root.querySelectorAll('[data-play]').forEach(b => b.addEventListener('click', async e => {
        e.stopPropagation();
        try { render(await api('/api/play', { id: b.dataset.play })); } catch (err) { offline(); }
      }));
    }

    // Channel sheet: watch, favourite, record now, and every programme with record / remind / catch-up
    async function openChannel(id) {
      openSheet('<p class="empty">Loading…</p>');
      try { drawChannel(await api('/api/channel?id=' + encodeURIComponent(id))); }
      catch (e) { openSheet('<p class="empty">Couldn’t load this channel.</p>'); }
    }
    async function channelAction(id, action, start) {
      try { drawChannel(await api('/api/channel/action', { id, action, start })); poll(); } catch (e) { offline(); }
    }
    function drawChannel(c) {
      if (!c.id) { openSheet('<p class="empty">Channel not found.</p>'); return; }
      const live = c.programmes.find(p => p.live);
      let day = '', rows = '';
      for (const p of c.programmes) {
        if (p.day !== day) { day = p.day; rows += `<div class="day">${esc(day)}</div>`; }
        const recOn = !!p.recording;
        rows += `<div class="prog ${p.past ? 'past' : ''}" data-start="${p.start}">
          <span class="tm">${esc(p.time.split('–')[0].trim())}</span>
          <div class="t"><div>${p.live ? '<span class="badge">LIVE</span>' : ''}${esc(p.title)}</div>
            <small>${esc(p.score || p.time)}${recOn ? ' · ⏺ ' + (p.recording === 'recording' ? 'recording' : 'set to record') : ''}${p.reminder ? ' · 🔔 reminder' : ''}</small></div>
          ${p.catchup && !p.live ? `<button class="b ic" data-act="catchup" title="Catch-up">↺</button>` : ''}
          ${!p.past ? `<button class="b ic rec ${recOn ? 'on' : ''}" data-act="${recOn ? 'cancelRecord' : 'record'}" title="Record">⏺</button>` : ''}
          ${p.future ? `<button class="b ic ${p.reminder ? 'on' : ''}" data-act="${p.reminder ? 'cancelRemind' : 'remind'}" title="Remind me">🔔</button>` : ''}
        </div>`;
      }
      const liveRec = live && live.recording;
      openSheet(`<div class="hd" style="align-items:center">
          ${c.logo ? `<img src="${esc(c.logo)}" style="width:80px;height:50px;object-fit:contain">` : ''}
          <div><h2>${c.number ? esc(c.number) + '  ' : ''}${esc(c.name)}</h2><div class="sub">${esc(c.group)}</div></div></div>
        <div class="acts"><button class="b primary" id="cwatch">▶ Watch</button>
          <button class="b" id="cfav">${c.favourite ? '★ Favourite' : '☆ Favourite'}</button></div>
        <div class="acts" style="margin-top:0"><button class="b ${liveRec ? 'primary' : ''}" id="crec" style="${liveRec ? 'background:var(--live)' : ''}">
          ${liveRec ? '■ Stop recording' : live ? '⏺ Record “' + esc(live.title) + '”' : '⏺ Record 1 hour'}</button></div>
        ${rows || '<p class="empty">No guide listings for this channel.</p>'}`);
      $('#cwatch').addEventListener('click', () => { closeSheet(); channelAction(c.id, 'watch'); });
      $('#cfav').addEventListener('click', () => channelAction(c.id, 'favourite'));
      $('#crec').addEventListener('click', () => channelAction(c.id, liveRec ? 'cancelRecord' : 'record', live ? live.start : undefined));
      $('#sheetcard').querySelectorAll('.prog').forEach(row => {
        const p = c.programmes.find(x => x.start === +row.dataset.start);
        row.querySelectorAll('[data-act]').forEach(b => b.addEventListener('click', e => {
          e.stopPropagation(); if (b.dataset.act === 'catchup') closeSheet(); channelAction(c.id, b.dataset.act, p.start); }));
        row.addEventListener('click', () => {
          if (p.live) { closeSheet(); channelAction(c.id, 'watch'); }
          else if (p.catchup) { closeSheet(); channelAction(c.id, 'catchup', p.start); }
        });
      });
    }
    let group = localStorage.getItem('mactvmate-group') || '';
    async function loadGroups() {
      try {
        const r = await api('/api/groups');
        if (!r.groups.some(g => g.name === group)) group = r.selected;
        $('#groups').innerHTML = r.groups.map(g =>
          `<button class="chip ${g.name === group ? 'sel' : ''}" data-g="${esc(g.name)}">${esc(g.name)}<small>${g.count}</small></button>`).join('');
        $('#groups').querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => {
          group = c.dataset.g;
          $('#groups').querySelectorAll('.chip').forEach(x => x.classList.toggle('sel', x === c));
          api('/api/group', { name: group }).catch(() => {});
          loadChannels();
        }));
        $('#groups .chip.sel')?.scrollIntoView({ inline: 'center', block: 'nearest' });
      } catch (e) {}
    }
    async function loadChannels() {
      if (!$('#groups').children.length) await loadGroups();
      localStorage.setItem('mactvmate-group', group);
      try {
        const r = await api('/api/channels?group=' + encodeURIComponent(group));
        $('#chlist').innerHTML = r.channels.map(c => itemHTML(c, c.title ? `${c.title} · ${c.time}` : '')).join('') ||
          '<p class="empty">No channels</p>';
        bindPlay($('#chlist'));
      } catch (e) { offline(); }
    }

    // Movies & shows
    const vod = { kind: 'movies', cat: '', q: '', offset: 0, cats: {} };
    async function openVOD(kind) {
      if (vod.kind !== kind) { vod.kind = kind; vod.cat = ''; vod.q = ''; $('#vq').value = ''; }
      $('#vq').placeholder = kind === 'movies' ? 'Search movies' : 'Search shows';
      loadVOD(false);
    }
    function posterHTML(it) {
      return `<div class="poster" data-id="${esc(it.id)}" data-kind="${esc(it.kind)}" data-inlist="${it.inList ? 1 : 0}">
        <div class="img" style="background-image:url('${esc(it.poster)}')"></div>
        ${it.rating ? `<span class="rt">${esc(it.rating)}</span>` : ''}${it.resume ? '<span class="rs">Resume</span>' : ''}
        <div class="nm">${esc(it.name)}</div></div>`;
    }
    function bindPosters(root) { root.querySelectorAll('.poster').forEach(el => el.addEventListener('click', () =>
      el.dataset.kind === 'series' ? openSeries(el.dataset.id) : openMovie(el))); }
    async function loadVOD(append) {
      if (!append) { vod.offset = 0; $('#vgrid').innerHTML = '<p class="empty">Loading…</p>'; }
      try {
        const r = await api(`/api/vod?kind=${vod.kind}&cat=${encodeURIComponent(vod.cat)}&q=${encodeURIComponent(vod.q)}&offset=${vod.offset}`);
        $('#cats').innerHTML = r.categories.map(c => `<button class="chip ${c.id === vod.cat ? 'sel' : ''}" data-c="${esc(c.id)}">${esc(c.name)}</button>`).join('');
        $('#cats').querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { vod.cat = c.dataset.c; loadVOD(false); }));
        if (!append) $('#cats .chip.sel')?.scrollIntoView({ inline: 'center', block: 'nearest' });
        const html = r.items.map(posterHTML).join('');
        if (append) $('#vgrid').insertAdjacentHTML('beforeend', html);
        else $('#vgrid').innerHTML = html || '<p class="empty" style="grid-column:1/-1">Nothing here</p>';
        bindPosters($('#vgrid'));
        vod.offset = r.offset + r.items.length;
        $('#vmore').style.display = vod.offset < r.total ? 'block' : 'none';
      } catch (e) { offline(); }
    }
    $('#vmore').addEventListener('click', () => loadVOD(true));
    let vt;
    $('#vq').addEventListener('input', () => { clearTimeout(vt); vt = setTimeout(() => { vod.q = $('#vq').value.trim(); loadVOD(false); }, 300); });

    // Detail sheets
    function openSheet(html) { $('#sheetcard').innerHTML = '<button class="b x" id="sx">✕</button>' + html; $('#sheet').classList.add('show');
      $('#sx').addEventListener('click', closeSheet); }
    function closeSheet() { $('#sheet').classList.remove('show'); }
    $('#sheet').addEventListener('click', e => { if (e.target.id === 'sheet') closeSheet(); });
    function listBtn(id, inList) { return `<button class="b" data-list="${esc(id)}">${inList ? '✓ In My list' : '＋ My list'}</button>`; }
    function bindList() { $('#sheetcard').querySelectorAll('[data-list]').forEach(b => b.addEventListener('click', async () => {
      try { const r = await api('/api/mylist', { id: b.dataset.list }); b.textContent = r.inList ? '✓ In My list' : '＋ My list'; } catch (e) {}
    })); }
    function openMovie(el) {
      const id = el.dataset.id, name = el.querySelector('.nm').textContent, img = el.querySelector('.img').style.backgroundImage;
      const rt = el.querySelector('.rt')?.textContent || '', resume = !!el.querySelector('.rs');
      openSheet(`<div class="hd"><div class="img" style='background-image:${img}'></div><div><h2>${esc(name)}</h2><div class="sub">${esc(rt)}</div></div></div>
        <div class="acts"><button class="b primary" id="mplay">▶ ${resume ? 'Resume' : 'Play'} on TV</button>${listBtn(id, el.dataset.inlist === '1')}</div>`);
      bindList();
      $('#mplay').addEventListener('click', async () => { closeSheet(); try { render(await api('/api/vod/play', { id })); } catch (e) { offline(); } });
    }
    async function openSeries(id) {
      openSheet('<p class="empty">Loading episodes…</p>');
      try {
        const s = await api('/api/series?id=' + encodeURIComponent(id));
        const seasons = s.seasons || [];
        let cur = seasons.length ? seasons[0].season : 0;
        if (s.next) for (const se of seasons) if (se.episodes.some(e => e.id === s.next.episode)) cur = se.season;
        const draw = () => {
          const se = seasons.find(x => x.season === cur);
          $('#eps').innerHTML = (se ? se.episodes : []).map(e => `<div class="ep" data-ep="${e.id}"><span class="no">${e.number}</span>
            <div class="t"><div>${esc(e.title)}</div>${e.resume ? '<span class="w">In progress</span>' : e.watched ? '<span class="w">✓ Last watched</span>' : ''}</div>
            <span class="d">${esc(e.duration)}</span></div>`).join('') || '<p class="empty">No episodes listed</p>';
          $('#eps').querySelectorAll('.ep').forEach(el => el.addEventListener('click', () => playEp(+el.dataset.ep)));
          $('#seasons').querySelectorAll('.chip').forEach(c => c.classList.toggle('sel', +c.dataset.s === cur));
        };
        const playEp = async ep => { closeSheet(); try { render(await api('/api/vod/play', { id, episode: ep })); } catch (e) { offline(); } };
        openSheet(`<div class="hd"><div class="img" style="background-image:url('${esc(s.poster)}')"></div>
          <div><h2>${esc(s.name)}</h2><div class="plot">${esc(s.plot)}</div></div></div>
          <div class="acts">${s.next ? `<button class="b primary" id="snext">▶ ${esc(s.next.label)}</button>` : ''}${listBtn(id, s.inList)}</div>
          <div class="chips" id="seasons">${seasons.map(x => `<button class="chip" data-s="${x.season}">Season ${x.season}</button>`).join('')}</div>
          <div id="eps"></div>`);
        bindList();
        if (s.next) $('#snext').addEventListener('click', () => playEp(s.next.episode));
        $('#seasons').querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { cur = +c.dataset.s; draw(); }));
        draw();
      } catch (e) { openSheet('<p class="empty">Couldn’t load this show.</p>'); }
    }

    // Library: recordings, reminders, favourites, My list
    async function loadLibrary() {
      try {
        const r = await api('/api/library');
        const rec = (x, btns) => `<div class="item" data-rec="${esc(x.id)}"><div class="t"><div class="nm">${esc(x.title)}</div>
          <div class="pg">${esc(x.channel)} · ${esc(x.time)}</div>${x.status === 'recording' ? '<div class="sc live">● Recording now</div>' : ''}</div>${btns}</div>`;
        $('#upcoming').innerHTML = r.upcoming.map(x => rec(x, `<button class="b go" data-ra="cancel" title="Cancel">✕</button>`)).join('') ||
          '<p class="empty">Nothing scheduled — open a channel in TV and tap ⏺ next to a programme.</p>';
        $('#recs').innerHTML = r.recordings.concat(r.failed || []).map(x => rec(x,
          (x.playable ? `<button class="b go" data-ra="play" title="Play">▶</button>` : '') +
          `<button class="b go" data-ra="delete" title="Delete">🗑</button>`)).join('') || '<p class="empty">No recordings yet</p>';
        $('#reminders').innerHTML = r.reminders.map(x => rec(x, `<button class="b go" data-ra="delete" title="Delete">✕</button>`)).join('') ||
          '<p class="empty">No reminders</p>';
        $('#v-library').querySelectorAll('[data-ra]').forEach(b => b.addEventListener('click', async () => {
          const id = b.closest('[data-rec]').dataset.rec, action = b.dataset.ra;
          if (action === 'delete' && !confirm('Delete this?')) return;
          try { await api('/api/recording/action', { id, action }); if (action === 'play') poll(); loadLibrary(); } catch (e) { offline(); }
        }));
        $('#favs').innerHTML = r.favourites.map(c => itemHTML(c)).join('') || '<p class="empty">Star channels with ☆ Favourite</p>';
        bindPlay($('#favs'));
        $('#mylist').innerHTML = r.myList.map(posterHTML).join('') || '<p class="empty" style="grid-column:1/-1">Add movies and shows with ＋ My list</p>';
        bindPosters($('#mylist'));
      } catch (e) { offline(); }
    }

    // Favourite / audio & subtitles / now-playing card
    $('#favbtn').addEventListener('click', async () => {
      const p = state.playing;
      if (p && p.id && p.live) { try { await api('/api/channel/action', { id: p.id, action: 'favourite' }); poll(); } catch (e) {} }
      else act('favourite');
    });
    $('#npt').addEventListener('click', () => { const p = state.playing; if (p && p.id && p.live) openChannel(p.id); });
    $('#tracksbtn').addEventListener('click', openTracks);
    async function openTracks() {
      try {
        const t = await api('/api/tracks');
        const row = (type, x) => `<div class="item" data-type="${type}" data-tid="${x.id ?? ''}"><div class="t"><div class="nm">${x.selected ? '✓ ' : ''}${esc(x.title)}</div></div></div>`;
        const subsOff = !t.subtitles.some(x => x.selected);
        openSheet(`<h2>Audio & subtitles</h2><h3>Audio</h3>${t.audio.map(x => row('audio', x)).join('') || '<p class="empty">Nothing playing</p>'}
          <h3>Subtitles</h3>${row('subtitles', { id: null, title: 'Off', selected: subsOff })}${t.subtitles.map(x => row('subtitles', x)).join('')}`);
        $('#sheetcard').querySelectorAll('[data-type]').forEach(el => el.addEventListener('click', async () => {
          const id = el.dataset.tid === '' ? null : +el.dataset.tid;
          try { await api('/api/tracks', { type: el.dataset.type, id }); openTracks(); } catch (e) {}
        }));
      } catch (e) { offline(); }
    }

    // Settings (everything except playlist logins, which stay on the Mac)
    $('#gear').addEventListener('click', openSettings);
    async function openSettings() {
      try { drawSettings(await api('/api/settings')); } catch (e) { offline(); }
    }
    function drawSettings(r) {
      let html = '<h2>Settings</h2>', section = '';
      for (const it of r.items) {
        if (it.section !== section) { section = it.section; html += `<h3>${esc(section)}</h3>`; }
        if (it.type === 'bool') {
          html += `<div class="set"><span>${esc(it.title)}</span><button class="sw ${it.value ? 'on' : ''}" data-key="${it.key}" data-bool="${it.value ? 1 : 0}"></button></div>`;
        } else if (it.key === 'accent') {
          html += `<div class="set"><span>${esc(it.title)}</span></div><div class="swatches">${it.options.map(o =>
            `<button class="${o.value === it.value ? 'on' : ''}" style="background:${o.hex}" data-key="accent" data-val="${esc(o.value)}" title="${esc(o.label)}"></button>`).join('')}</div>`;
        } else {
          html += `<div class="set"><span>${esc(it.title)}</span><select data-key="${it.key}">${it.options.map(o =>
            `<option value="${o.value}" ${o.value === it.value ? 'selected' : ''}>${esc(o.label)}</option>`).join('')}</select></div>`;
        }
      }
      html += `<p class="hint" style="text-align:left">Display: ${esc(r.display)}</p>`;
      html += `<h3>Playlist & guide</h3><div class="set"><span>${esc(r.status)}</span><button class="b" id="reload" style="padding:10px 14px;border-radius:10px">Update now</button></div>`;
      html += r.guide.map(g => `<div class="set"><span>${g.ok ? '✅' : '⚠️'} ${esc(g.name)}<br><small style="color:var(--dim)">${esc(g.note)}</small></span></div>`).join('');
      html += `<h3>Channel groups</h3>` + r.groups.map(g => `<div class="set"><span>${esc(g.name)} <small style="color:var(--faint)">${g.count}${g.locked ? ' · hidden by adult filter' : ''}</small></span>
        <button class="sw ${g.hidden ? '' : 'on'}" data-group="${esc(g.name)}" data-hidden="${g.hidden ? 1 : 0}" ${g.locked ? 'disabled' : ''}></button></div>`).join('');
      html += `<p class="hint">Playlists and provider logins are edited on the Mac (Settings ▸ Playlists) so they never travel over Wi-Fi.</p>`;
      openSheet(html);
      const card = $('#sheetcard');
      card.querySelectorAll('.sw[data-key]').forEach(b => b.addEventListener('click', () => setSetting(b.dataset.key, b.dataset.bool !== '1')));
      card.querySelectorAll('select[data-key]').forEach(sel => sel.addEventListener('change', () => setSetting(sel.dataset.key, +sel.value)));
      card.querySelectorAll('.swatches [data-key]').forEach(b => b.addEventListener('click', () => setSetting('accent', b.dataset.val)));
      card.querySelectorAll('.sw[data-group]').forEach(b => b.addEventListener('click', async () => {
        try { drawSettings(await api('/api/settings/group', { name: b.dataset.group, hidden: b.dataset.hidden !== '1' })); } catch (e) {}
      }));
      $('#reload').addEventListener('click', async () => { try { await api('/api/reload', {}); $('#reload').textContent = 'Updating…'; } catch (e) {} });
    }
    async function setSetting(key, value) {
      const y = $('#sheetcard').scrollTop;
      try { drawSettings(await api('/api/settings', { key, value })); $('#sheetcard').scrollTop = y; } catch (e) { offline(); }
    }

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
      clearTimeout(et); et = setTimeout(() => { entry = ''; $('#entry').textContent = 'Channel number'; }, 1600);
    }));
    </script>
    </body>
    </html>
    """#
}
