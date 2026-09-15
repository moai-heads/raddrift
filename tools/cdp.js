// Boot the page in headless chromium via CDP, collect console/exceptions, screenshot.
const { spawn } = require("child_process");
const fs = require("fs");
const http = require("http");

const URL = process.argv[2] || "http://127.0.0.1:8099/index.html";
const OUT = process.argv[3] || "/root/raddrift/live.png";

function get(path) {
  return new Promise((res, rej) => http.get({ host: "127.0.0.1", port: 9222, path }, r => {
    let d = ""; r.on("data", c => d += c); r.on("end", () => res(d));
  }).on("error", rej));
}

(async () => {
  const chrome = spawn("chromium", [
    "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
    "--remote-debugging-port=9222", "--window-size=1280,720",
    "--autoplay-policy=no-user-gesture-required",
    "--use-gl=swiftshader", "--enable-unsafe-swiftshader",
    "about:blank"
  ], { stdio: "ignore" });

  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    try {
      const list = JSON.parse(await get("/json/list"));
      target = list.find(t => t.type === "page");
    } catch (e) {}
    if (!target) await new Promise(r => setTimeout(r, 250));
  }
  if (!target) { console.log("no target"); chrome.kill(); process.exit(1); }

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const logs = [];
  const send = (method, params) => new Promise(res => {
    const mid = ++id; pending.set(mid, res);
    ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
  });

  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result); pending.delete(msg.id); }
    if (msg.method === "Runtime.consoleAPICalled") {
      logs.push("[console." + msg.params.type + "] " + msg.params.args.map(a => a.value ?? a.description ?? JSON.stringify(a.preview||"")).join(" "));
    }
    if (msg.method === "Runtime.exceptionThrown") {
      const d = msg.params.exceptionDetails;
      logs.push("[EXCEPTION] " + (d.exception?.description || d.text));
    }
    if (msg.method === "Log.entryAdded") {
      logs.push("[" + msg.params.entry.level + "] " + msg.params.entry.text);
    }
  };

  await new Promise(r => ws.onopen = r);
  await send("Runtime.enable");
  await send("Log.enable");
  await send("Page.enable");
  await send("Page.navigate", { url: URL });
  await new Promise(r => setTimeout(r, 3500));

  // screenshot
  const shot = await send("Page.captureScreenshot", { format: "png" });
  if (shot && shot.data) fs.writeFileSync(OUT, Buffer.from(shot.data, "base64"));

  // probe game state via JS
  const probe = await send("Runtime.evaluate", { expression: "(function(){try{return JSON.stringify({ok:typeof WebAssembly!=='undefined'})}catch(e){return 'err:'+e}})()", returnByValue: true });
  console.log("probe:", probe && probe.result && probe.result.value);

  console.log("--- logs ---");
  console.log(logs.length ? logs.join("\n") : "(no console output)");
  ws.close(); chrome.kill();
})();
