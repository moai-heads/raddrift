// Competent bot: local threat-field avoidance incl. enemy bullets, shard magnet, card picks.
const fs=require("fs");
const mod=new WebAssembly.Module(fs.readFileSync(__dirname + "/../main.wasm"));
function run(seed,maxSec,verbose){
  const X=new WebAssembly.Instance(mod,{}).exports;
  X.init(seed); X.key(32,1);X.key(32,0);
  const held={W:0,A:0,S:0,D:0};
  const set=(k,v)=>{v=v?1:0; if(held[k]===v)return; held[k]=v; X.key({W:87,A:65,S:83,D:68}[k],v);};
  let t=0,maxT=0,cards=0;
  for(let i=0;i<60*maxSec;i++){
    const px=X.dbg_px(),py=X.dbg_py();
    // threat field: repel from enemies (weighted by range) + bullets prediction
    let fx=0,fy=0;
    const n=X.dbg_count_enemies();
    for(let e=0;e<n;e++){
      const ex=X.dbg_ex(e),ey=X.dbg_ey(e);
      const dx=px-ex,dy=py-ey; const d2=dx*dx+dy*dy;
      if(d2<170*170&&d2>0.01){ const w=1/(d2+40); fx+=dx*w*900; fy+=dy*w*900; }
    }
    const nb=X.dbg_nbullets();
    for(let b=0;b<nb;b++){
      if(!X.dbg_benemy(b))continue;
      const bx=X.dbg_bx(b),by=X.dbg_by(b),vx=X.dbg_bvx(b),vy=X.dbg_bvy(b);
      // closest approach distance from a point 26px ahead
      for(let s=0;s<=0.7;s+=0.2){
        const qx=bx+vx*s,qy=by+vy*s; const dx=px-qx,dy=py-qy; const d2=dx*dx+dy*dy;
        if(d2<70*70){ const w=(1/(d2+30))*2500; fx+=dx*w; fy+=dy*w; }
      }
    }
    // shards
    const nc=X.dbg_ncrystals();
    for(let c=0;c<nc;c++){ const dx=X.dbg_cx(c)-px,dy=X.dbg_cy(c)-py; const d2=dx*dx+dy*dy;
      if(d2<140*140&&d2>1){ fx+=dx/d2*260; fy+=dy/d2*260; } }
    // walls
    if(px<34)fx+=4; if(px>446)fx-=4; if(py<34)fy+=4; if(py>236)fy-=4;
    // dash away if threat is high & cooldown ready (dash also damages)
    let threatMag=Math.hypot(fx,fy);
    if(threatMag>6 && (i%3===0)){ X.key(32,1); X.key(32,0); }
    set("D",fx>0.12); set("A",fx<-0.12); set("S",fy>0.12); set("W",fy<-0.12);
    X.frame(16.7);
    const st=X.dbg_state();
    if(st===2){ const pick=(seed+cards)%3; X.key(49+pick,1);X.key(49+pick,0); cards++; X.frame(16.7); }
    else if(st===3) return {t:X.dbg_time(),kills:X.dbg_kills(),cards,score:X.dbg_score(),wave:X.dbg_wave_n()};
    maxT=X.dbg_time();
  }
  return {t:maxT,kills:X.dbg_kills(),cards,score:X.dbg_score(),wave:X.dbg_wave_n()};
}
const seeds=[1,2,3,42,1337,9999,555];
let sum=0,best=0,worst=1e9;
for(const s of seeds){const r=run(s,600,false);sum+=r.t;best=Math.max(best,r.t);worst=Math.min(worst,r.t);
  console.log(`seed ${s}: ${r.t.toFixed(1)}s wave ${r.wave} kills ${r.kills} cards ${r.cards} score ${r.score.toFixed(0)}`);}
console.log(`avg ${(sum/seeds.length).toFixed(1)}s  best ${best.toFixed(1)}s  worst ${worst.toFixed(1)}s`);
