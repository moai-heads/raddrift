// Kiting bot: flee enemy centroid, hoover shards. Measures natural survival time.
const fs=require("fs");
const mod=new WebAssembly.Module(fs.readFileSync(__dirname + "/../web/raddrift.wasm"));
function run(seed, maxSec, smart){
  const X=new WebAssembly.Instance(mod,{}).exports;
  X.init(seed);
  X.key(32,1);X.key(32,0);
  const keys={W:87,A:65,S:83,D:68};
  let held={};
  const set=(k,v)=>{ if(!!held[k]===!!v)return; held[k]=v; X.key(keys[k],v?1:0); };
  let maxT=0;
  for(let i=0;i<60*maxSec;i++){
    if(smart){
      const px=X.dbg_px(),py=X.dbg_py();
      const n=X.dbg_count_enemies();
      let fx=0,fy=0;
      for(let e=0;e<n;e++){ const k=X.dbg_ekind(e); if(k===4)continue; // ignore hazard
        const dx=px-X.dbg_ex(e), dy=py-X.dbg_ey(e); const d2=dx*dx+dy*dy+1;
        fx+=dx/d2; fy+=dy/d2; }
      // shard attraction
      const nc=X.dbg_ncrystals();
      let gx=0,gy=0;
      for(let c=0;c<nc;c++){ const dx=X.dbg_cx(c)-px, dy=X.dbg_cy(c)-py; const d2=dx*dx+dy*dy+1;
        if(d2<160*160){ gx+=dx/d2; gy+=dy/d2; } }
      let vx=fx*900+gx*300, vy=fy*900+gy*300;
      // keep off walls
      if(px<40)vx+=3; if(px>440)vx-=3; if(py<40)vy+=3; if(py>230)vy-=3;
      set("D",vx>0.15); set("A",vx<-0.15); set("S",vy>0.15); set("W",vy<-0.15);
    } else {
      if(i%7===0) X.key(keys[["W","A","S","D"][(Math.random()*4)|0]],1);
      if(i%11===0) for(const k in keys) X.key(keys[k],0);
    }
    X.frame(16.7);
    if(X.dbg_state()===2){ X.key(49,1);X.key(49,0); X.frame(16.7); }
    if(X.dbg_state()===3){
      if(smart) return X.dbg_time(); else { X.key(32,1);X.key(32,0); X.frame(16.7); }
    }
    maxT=Math.max(maxT,X.dbg_time());
  }
  return maxT;
}
const seeds=[1,2,3,42,1337,9999];
console.log("=== random-input bot ===");
for(const s of seeds) console.log("seed",s,"survived",run(s,90,false).toFixed(1)+"s");
console.log("=== kiting bot ===");
let tot=0;for(const s of seeds){const t=run(s,300,true);tot+=t;console.log("seed",s,"survived",t.toFixed(1)+"s");}
console.log("avg kite survival",(tot/seeds.length).toFixed(1)+"s");
