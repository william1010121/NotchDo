/// The progress page, embedded because the app bundle is built from a bare executable and
/// SwiftPM resource bundles are not copied into it. All task text is inserted with
/// `textContent`, never as HTML.
enum ProgressPageAssets {
    static let indexHTML = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>NotchDo AI</title>
    <style>
    :root {
      --bg: #f4f5f6; --surface: #ffffff; --ink: #15181c; --muted: #5d6671; --line: #dde1e5;
      --signal: #0b8a68; --signal-soft: #dcf2ea; --amber: #a85d00; --amber-soft: #fbead0;
      --red: #b3321f; --red-soft: #f9dfda; --code: #eceef0;
      --mono: ui-monospace, "SF Mono", Menlo, monospace;
      color-scheme: light;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0e1012; --surface: #16191c; --ink: #e8ebee; --muted: #98a2ad; --line: #2a2f35;
        --signal: #3fd0a3; --signal-soft: #12362b; --amber: #f0b45a; --amber-soft: #3a2a10;
        --red: #f08a78; --red-soft: #3b1d17; --code: #1f2327; color-scheme: dark;
      }
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    header { display: flex; align-items: baseline; gap: 12px; padding: 16px 20px; border-bottom: 1px solid var(--line); }
    header h1 { font-size: 17px; margin: 0; }
    #conn { font: 12px var(--mono); color: var(--muted); }
    #conn.live::before { content: "● "; color: var(--signal); }
    #conn.down::before { content: "● "; color: var(--red); }
    main { display: grid; grid-template-columns: minmax(260px, 340px) minmax(0, 1fr); min-height: calc(100vh - 54px); }
    #list { border-right: 1px solid var(--line); overflow-y: auto; }
    .task { display: block; width: 100%; text-align: left; border: 0; border-bottom: 1px solid var(--line); background: none; color: inherit; font: inherit; padding: 12px 20px; cursor: pointer; }
    .task:hover, .task:focus-visible { background: var(--surface); outline: none; }
    .task[aria-current="true"] { background: var(--surface); box-shadow: inset 3px 0 0 var(--signal); }
    .task .title { font-weight: 600; overflow-wrap: anywhere; }
    .task .sub { font-size: 13px; color: var(--muted); overflow-wrap: anywhere; }
    .pill { display: inline-block; font: 11.5px var(--mono); padding: 0 8px; border-radius: 99px; margin-right: 6px; background: var(--code); color: var(--muted); }
    .pill.running, .pill.done { background: var(--signal-soft); color: var(--signal); }
    .pill.queued { background: var(--amber-soft); color: var(--amber); }
    .pill.failed { background: var(--red-soft); color: var(--red); }
    #detail { padding: 20px 28px 64px; min-width: 0; }
    #detail h2 { margin: 0 0 4px; font-size: 22px; overflow-wrap: anywhere; }
    .meta { font: 12.5px var(--mono); color: var(--muted); display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 6px 0 18px; }
    h3 { font-size: 13px; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 24px 0 8px; }
    .block { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; white-space: pre-wrap; overflow-wrap: anywhere; }
    .block.error { border-color: var(--red); color: var(--red); }
    a { color: var(--signal); }
    .links a { display: inline-block; margin: 0 12px 6px 0; }
    ol.timeline { list-style: none; margin: 0; padding: 0; border-left: 2px solid var(--line); }
    ol.timeline li { padding: 2px 0 8px 16px; position: relative; overflow-wrap: anywhere; }
    ol.timeline li::before { content: ""; position: absolute; left: -6px; top: 10px; width: 10px; height: 10px; border-radius: 50%; background: var(--bg); border: 2px solid var(--line); }
    ol.timeline li.tool::before { border-color: var(--signal); }
    ol.timeline .name { font: 12.5px var(--mono); color: var(--signal); margin-right: 8px; }
    ol.timeline .detail { font: 12.5px var(--mono); color: var(--muted); }
    .empty { color: var(--muted); padding: 40px 20px; }
    @media (max-width: 760px) {
      main { grid-template-columns: minmax(0, 1fr); }
      #list { border-right: 0; border-bottom: 1px solid var(--line); max-height: 40vh; }
      #detail { padding: 16px; }
    }
    @media (prefers-reduced-motion: no-preference) { .pill.running { animation: pulse 1.6s ease-in-out infinite; } }
    @keyframes pulse { 50% { opacity: .55; } }
    </style>
    </head>
    <body>
    <header><h1>NotchDo AI</h1><span id="conn" class="down" role="status">connecting</span></header>
    <main>
      <nav id="list" aria-label="AI tasks"></nav>
      <section id="detail" aria-live="polite"><p class="empty">Select a task.</p></section>
    </main>
    <script>
    "use strict";
    var tasks = [];
    var selected = null;
    var timeline = {};   // id -> { next: Number, items: [] }
    var detailCache = {}; // id -> { result }

    function el(tag, className, text) {
      var node = document.createElement(tag);
      if (className) node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    }
    function ago(iso) {
      if (!iso) return "";
      var seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
      if (seconds < 60) return "just now";
      if (seconds < 3600) return Math.floor(seconds / 60) + " min ago";
      if (seconds < 86400) return Math.floor(seconds / 3600) + " h ago";
      return new Date(iso).toLocaleDateString();
    }
    function duration(task) {
      if (!task.startedAt) return "";
      var end = task.finishedAt ? new Date(task.finishedAt) : new Date();
      var s = Math.max(0, Math.round((end - new Date(task.startedAt)) / 1000));
      return s < 60 ? s + " s" : Math.floor(s / 60) + " min " + (s % 60) + " s";
    }
    function subtitle(task) {
      if (task.status === "running") return task.lastActivity || "Working…";
      if (task.status === "failed") return task.errorMessage || "Failed";
      if (task.status === "done") return (task.summary || "Done").split("\n")[0];
      return task.status === "queued" ? "Queued" : "Cancelled";
    }
    function pill(status) { return el("span", "pill " + status, status); }
    function safeLink(url) {
      return /^https:\/\/claude\.ai\//.test(url) ? url : null;
    }

    function renderList() {
      var list = document.getElementById("list");
      list.textContent = "";
      if (!tasks.length) {
        list.appendChild(el("p", "empty", "No AI tasks yet. Press ⌃⌥E anywhere to add one."));
        return;
      }
      tasks.forEach(function (task) {
        var button = el("button", "task");
        button.type = "button";
        if (task.id === selected) button.setAttribute("aria-current", "true");
        var title = el("div", "title");
        title.appendChild(pill(task.status));
        title.appendChild(document.createTextNode(task.title));
        button.appendChild(title);
        button.appendChild(el("div", "sub", subtitle(task)));
        button.addEventListener("click", function () { select(task.id); });
        list.appendChild(button);
      });
    }

    function renderDetail() {
      var root = document.getElementById("detail");
      var task = tasks.filter(function (t) { return t.id === selected; })[0];
      root.textContent = "";
      if (!task) { root.appendChild(el("p", "empty", "Select a task.")); return; }
      root.appendChild(el("h2", null, task.title));
      var meta = el("div", "meta");
      meta.appendChild(pill(task.status));
      [ago(task.createdAt), duration(task), task.turnCount ? task.turnCount + " turns" : "",
       typeof task.costUSD === "number" ? "$" + task.costUSD.toFixed(2) : ""].forEach(function (text) {
        if (text) meta.appendChild(el("span", null, text));
      });
      root.appendChild(meta);

      if (task.status === "running") {
        root.appendChild(el("h3", null, "Now"));
        root.appendChild(el("div", "block", task.lastActivity || "Working…"));
      }
      if (task.status === "failed" && task.errorMessage) {
        root.appendChild(el("h3", null, "Error"));
        root.appendChild(el("div", "block error", task.errorMessage));
      }
      var links = (task.artifactURLs || []).map(safeLink).filter(Boolean);
      if (links.length) {
        root.appendChild(el("h3", null, "Artifacts"));
        var box = el("div", "links");
        links.forEach(function (url) {
          var a = el("a", null, url.replace("https://", ""));
          a.href = url; a.target = "_blank"; a.rel = "noopener noreferrer";
          box.appendChild(a);
        });
        root.appendChild(box);
      }
      var cached = detailCache[task.id];
      if (cached && cached.result) {
        root.appendChild(el("h3", null, "Result"));
        root.appendChild(el("div", "block", cached.result));
      }
      root.appendChild(el("h3", null, "Request"));
      root.appendChild(el("div", "block", task.prompt));
      (task.followUps || []).forEach(function (text) {
        root.appendChild(el("h3", null, "Follow-up"));
        root.appendChild(el("div", "block", text));
      });
      var items = (timeline[task.id] || { items: [] }).items;
      if (items.length) {
        root.appendChild(el("h3", null, "Activity"));
        var ol = el("ol", "timeline");
        items.forEach(function (item) {
          var li = el("li", item.kind);
          if (item.kind === "tool") {
            li.appendChild(el("span", "name", item.name));
            if (item.detail) li.appendChild(el("span", "detail", item.detail));
          } else {
            li.textContent = item.text;
          }
          ol.appendChild(li);
        });
        root.appendChild(ol);
      }
    }

    function parseLine(line, items) {
      var obj;
      try { obj = JSON.parse(line); } catch (e) { return; }
      if (obj.type !== "assistant" || !obj.message || !Array.isArray(obj.message.content)) return;
      obj.message.content.forEach(function (block) {
        if (block.type === "text" && block.text && block.text.trim()) {
          items.push({ kind: "text", text: block.text.trim() });
        } else if (block.type === "tool_use") {
          var input = block.input || {};
          var detail = input.file_path || input.path || input.command || input.pattern || input.url || input.action || "";
          items.push({ kind: "tool", name: block.name, detail: String(detail).split("\n")[0].slice(0, 120) });
        }
      });
    }

    function refreshDetail() {
      if (!selected) return;
      var id = selected;
      var state = timeline[id] || (timeline[id] = { next: 0, items: [] });
      Promise.all([
        fetch("/api/tasks/" + id).then(function (r) { return r.json(); }),
        fetch("/api/tasks/" + id + "/events?after=" + state.next).then(function (r) { return r.json(); })
      ]).then(function (parts) {
        detailCache[id] = { result: parts[0].result };
        parts[1].lines.forEach(function (line) { parseLine(line, state.items); });
        state.next = parts[1].next;
        if (id === selected) renderDetail();
      }).catch(function () {});
    }

    function select(id) {
      selected = id;
      try { history.replaceState(null, "", "#" + id); } catch (e) {}
      renderList(); renderDetail(); refreshDetail();
    }

    function setConnection(live) {
      var node = document.getElementById("conn");
      node.className = live ? "live" : "down";
      node.textContent = live ? "live" : "reconnecting";
    }

    function connect() {
      var source = new EventSource("/api/stream");
      source.onopen = function () { setConnection(true); };
      source.onerror = function () { setConnection(false); };
      source.addEventListener("tasks", function (event) {
        tasks = JSON.parse(event.data);
        if (!selected && tasks.length) selected = tasks[0].id;
        renderList(); renderDetail(); refreshDetail();
      });
    }

    var hash = location.hash.replace("#", "");
    if (/^[0-9A-Fa-f-]{36}$/.test(hash)) selected = hash;
    connect();
    setInterval(function () { renderList(); renderDetail(); }, 15000);
    </script>
    </body>
    </html>
    """#
}
