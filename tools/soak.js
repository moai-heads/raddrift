// Long-run soak: random-ish input, forced levels/waves, watch for traps.
const fs=require("fs");
const mod=new WebAssembly.Module(fs.readFileSync(__dirname + "/../main.wasm"));
const X=new WebAssembly.Instance(mod,{}).exports;
X.init(4242);
X.key(32,1);X.key(32,0); // start
let maxEn=0,maxBul=0,maxPar=0,bad=0;
const K=[87,65,83,68];
for(let i=0;i<60*120;i++){ // ~2 min at 60fps
  if(i%7===0){const k=K[(Math.random()*4)|0];X.key(k,1);}
  if(i%11===0){for(const k of K)X.key(k,0);}
  if(i%300===0){X.key(32,1);} if(i%300===5){X.key(32,0);}
  if(i%400===0){ // spawn pressure
    for(let j=0;j<12;j++){const a=Math.random()*6.283;X.dbg_spawn((Math.random()*6)|0,240+Math.cos(a)*(40+Math.random()*240),135+Math.sin(a)*(30+Math.random()*150));}
  }
  if(i%900===0){X.dbg_give_xp(60);} // force level-ups -> card screens
  if(i%90<30){ // pick a card if up
    if(X.dbg_state()===2){X.key(49+((i/90)|0)%3,1);X.key(49,0);}
  }
  X.frame(16.7);
  const s=X.dbg_state();
  if(s<0||s>4){bad++;}
  maxEn=Math.max(maxEn,X.dbg_count_enemies());
  maxBul=Math.max(maxBul,X.dbg_count_bullets());
  if(i%1200===0){
    console.log("t="+ (i/60).toFixed(0)+"s state",s,"en",X.dbg_count_enemies(),"bul",X.dbg_count_bullets(),"kills",X.dbg_kills(),"hp",X.dbg_hp().toFixed(1),"score",X.dbg_score(),"time",X.dbg_time().toFixed(1));
  }
}
console.log("SOAK OK  maxEnemies",maxEn,"maxBullets",maxBul,"badState",bad,"finalKills",X.dbg_kills(),"score",X.dbg_score());
