const fs=require("fs");
const X=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(__dirname + "/../main.wasm")),{}).exports;
X.init(4242);
X.key(32,1);X.key(32,0);
let prev=X.dbg_state(),deaths=0,restarts=0,lastKind=-1;
const K=[87,65,83,68];
for(let i=0;i<60*90;i++){
  if(i%7===0)X.key(K[(Math.random()*4)|0],1);
  if(i%11===0)for(const k of K)X.key(k,0);
  if(i===200)X.key(32,1); if(i===205)X.key(32,0);
  if(i%400===0)for(let j=0;j<12;j++){const a=Math.random()*6.283;X.dbg_spawn((Math.random()*6)|0,240+Math.cos(a)*(40+Math.random()*240),135+Math.sin(a)*(30+Math.random()*150));}
  if(i%900===0)X.dbg_give_xp(60);
  X.frame(16.7);
  const s=X.dbg_state();
  if(s!==prev){
    console.log("frame",i,"t="+(i/60).toFixed(1)+"s state",prev,"->",s,"| hp",X.dbg_hp().toFixed(1),"time",X.dbg_time().toFixed(1),"kills",X.dbg_kills());
    if(prev===1&&s===3)deaths++;
    if(prev===0&&s===1)restarts++;
    prev=s;
  }
}
console.log("deaths",deaths,"startsFromTitle",restarts);
