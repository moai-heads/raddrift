const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const http = require("http");

const SITE = __dirname + "/../web";
const PORT = 8124, DBG = 9333;
const MIME = {".html":"text/html",".js":"text/javascript",".wasm":"application/wasm",".png":"image/png"};

const server = http.createServer((req,res)=>{
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p === "/") p = "/index.html";
  if (p === "/favicon.ico") p = "/favicon.svg";
  const f = path.join(SITE, p);
  fs.readFile(f, (e,d)=> e ? (console.log("404:", p), res.writeHead(404), res.end("nf")) :
    (res.writeHead(200,{"Content-Type":MIME[path.extname(f)]||"application/octet-stream","Cross-Origin-Opener-Policy":"same-origin","Cross-Origin-Embedder-Policy":"require-corp"}), res.end(d)));
});

const get = p => new Promise((res,rej)=>http.get({host:"127.0.0.1",port:DBG,path:p},r=>{let d="";r.on("data",c=>d+=c);r.on("end",()=>res(d))}).on("error",rej));

(async () => {
  await new Promise(r=>server.listen(PORT, r));
  const chrome = spawn("chromium", ["--headless=new","--no-sandbox","--disable-gpu","--disable-dev-shm-usage",
    "--remote-debugging-port="+DBG,"--window-size=1280,760","--autoplay-policy=no-user-gesture-required",
    "--user-data-dir=/tmp/rd_"+Date.now(),"--use-gl=swiftshader","--enable-unsafe-swiftshader","about:blank"], {stdio:"ignore"});
  let target=null;
  for (let i=0;i<80&&!target;i++){ try{const l=JSON.parse(await get("/json/list"));target=l.find(t=>t.type==="page");}catch(e){} if(!target)await new Promise(r=>setTimeout(r,200)); }
  if(!target){console.log("no target");process.exit(1);}
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id=0; const pend=new Map(); const logs=[];
  const send=(m,p)=>new Promise(res=>{const i=++id;pend.set(i,res);ws.send(JSON.stringify({id:i,method:m,params:p||{}}))});
  ws.onmessage=m=>{const o=JSON.parse(m.data); if(o.id&&pend.has(o.id)){pend.get(o.id)(o.result);pend.delete(o.id);}
    if(o.method==="Runtime.exceptionThrown")logs.push("EXC "+(o.params.exceptionDetails.exception?.description||o.params.exceptionDetails.text));
    if(o.method==="Runtime.consoleAPICalled")logs.push("LOG "+o.params.args.map(a=>a.value??a.description).join(" "));
    if(o.method==="Log.entryAdded")logs.push(o.params.entry.level+": "+o.params.entry.text);};
  await new Promise(r=>ws.onopen=r);
  await send("Runtime.enable"); await send("Log.enable"); await send("Page.enable");
  await send("Page.navigate",{url:`http://127.0.0.1:${PORT}/index.html`});
  await new Promise(r=>setTimeout(r,3000));
  const shot=async n=>{
    const r = await ev("JSON.stringify(document.getElementById('c').getBoundingClientRect())");
    const b = JSON.parse(r); const clip={x:Math.round(b.x),y:Math.round(b.y),width:Math.round(b.width),height:Math.round(b.height),scale:1};
    const s=await send("Page.captureScreenshot",{format:"png",clip});
    fs.writeFileSync("/root/raddrift/"+n,Buffer.from(s.data,"base64"));};
  const key=(c,d)=>send("Runtime.evaluate",{expression:`window.dispatchEvent(new KeyboardEvent('${d?'keydown':'keyup'}',{keyCode:${c},code:'X',bubbles:true}))`});
  const ev=async e=>(await send("Runtime.evaluate",{expression:e,returnByValue:true})).result?.value;

  console.log("ready?", await ev("!!window.__rd"));
  await shot("b_title.png");
  await key(32,true); await key(32,false);
  await new Promise(r=>setTimeout(r,300));
  // run toward a corner while holding fire (auto-fire is automatic)
  await key(68,true); await key(83,true);
  await new Promise(r=>setTimeout(r,700));
  await key(65,true); await key(87,true);
  await new Promise(r=>setTimeout(r,700));
  // sprinkle enemies around the player for a busy frame
  await ev("for(let k=0;k<4;k++)for(let j=0;j<7;j++){const a=Math.random()*6.283;__rd.dbg_spawn(k, 240+Math.cos(a)*(50+j*20),135+Math.sin(a)*(38+j*12));}");
  await new Promise(r=>setTimeout(r,1600));
  console.log("mid:", "state",await ev("__rd.dbg_state()"),"time",await ev("__rd.dbg_time()"),"en",await ev("__rd.dbg_count_enemies()"),"bul",await ev("__rd.dbg_count_bullets()"),"kills",await ev("__rd.dbg_kills()"),"hp",await ev("__rd.dbg_hp()"));
  await shot("b_play.png");
  // level up -> cards
  await ev("__rd.dbg_give_xp(1000)");
  await new Promise(r=>setTimeout(r,500));
  console.log("after xp state:", await ev("__rd.dbg_state()"));
  await shot("b_cards.png");
  console.log("logs:", logs.length?logs.join(" | "):"(none)");
  ws.close(); chrome.kill(); server.close();
  process.exit(0);
})();
