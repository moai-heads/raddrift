// Headless test drive: run the wasm game, dump frames as PPM.
const fs = require("fs");
const mod = new WebAssembly.Module(fs.readFileSync(__dirname + "/../web/raddrift.wasm"));
const X = new WebAssembly.Instance(mod, {}).exports;
const W = X.fw(), H = X.fh();

function dump(name) {
  const ptr = X.fbptr();
  const px = new Uint8Array(X.memory.buffer, ptr, W * H * 4);
  const out = Buffer.alloc(15 + W * H * 3);
  const head = Buffer.from(`P6\n${W} ${H}\n255\n`, "ascii");
  head.copy(out, 0);
  let o = 15;
  for (let i = 0; i < W * H; i++) {
    out[o++] = px[i*4]; out[o++] = px[i*4+1]; out[o++] = px[i*4+2];
  }
  fs.writeFileSync(__dirname + "/" + name, out);
  console.log("wrote", name, W + "x" + H);
}

function frames(n, dt) { for (let i=0;i<n;i++) X.frame(dt); }

X.init(1337);
// title
frames(40, 16.7); dump("shot_title.ppm");

// start
X.key(32, 1); X.key(32, 0);
frames(6, 16.7);

// move around + shoot: hold D and W a while, dash
for (let i=0;i<180;i++){
  X.key(68,1); X.key(87,1);
  if (i===60){ X.key(32,1);} if(i===64){X.key(32,0);}
  X.frame(16.7);
}
X.key(68,0); X.key(87,0);

// spawn a bunch of enemies of each kind for a busy frame
for (let k=0;k<6;k++){
  for (let j=0;j<6;j++){
    const ang = Math.random()*6.283;
    X.dbg_spawn(k, 240+Math.cos(ang)*(60+j*22), 135+Math.sin(ang)*(40+j*14));
  }
}
frames(90, 16.7);
dump("shot_play.ppm");

// force a level up
X.dbg_give_xp(1000);
X.frame(16.7);
frames(8, 16.7);
dump("shot_cards.ppm");

console.log("state", X.dbg_state(), "kills", X.dbg_kills(), "enemies", X.dbg_count_enemies(), "bullets", X.dbg_count_bullets());
