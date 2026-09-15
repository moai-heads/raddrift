const fs=require("fs");
const X=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(__dirname + "/../main.wasm")),{}).exports;
X.init(7);
let prev=X.dbg_state();
const K=[87,65,83,68];
const log=(tag)=>{console.log(`[f${i} t=${(X.dbg_time()).toFixed(1)}] ${tag} state=${X.dbg_state()} hp=${X.dbg_hp().toFixed(0)} kills=${X.dbg_kills()} score=${X.dbg_score().toFixed(0)} en=${X.dbg_count_enemies()}`);};
let i=0;
const ev=(fn)=>{ // run one frame then check transition
  X.frame(16.7);
  const s=X.dbg_state();
  if(s!==prev){log(`${prev}->${s}`);prev=s;}
};
// title -> play
X.key(32,1);X.key(32,0);ev();
for(i=0;i<60*75;i++){
  if(i%5===0)X.key(K[(Math.random()*4)|0],1);
  if(i%9===0)for(const k of K)X.key(k,0);
  if(i%240===0){X.key(32,1);} if(i%240===4){X.key(32,0);} // dash
  if(i%360===0)for(let j=0;j<10;j++){const a=Math.random()*6.283;X.dbg_spawn((Math.random()*6)|0,240+Math.cos(a)*(40+Math.random()*220),135+Math.sin(a)*(30+Math.random()*140));}
  X.frame(16.7);
  let s=X.dbg_state();
  if(s!==prev){log(`${prev}->${s}`);prev=s;}
  if(s===2){ // card screen: pick one
    X.key(49+(i%3),1);X.key(49+(i%3),0);ev();
  }
  if(s===3){ log("DIED"); X.key(32,1);X.key(32,0);ev(); } // retry
}
console.log("FINAL state",X.dbg_state(),"kills",X.dbg_kills(),"score",X.dbg_score().toFixed(0),"time",X.dbg_time().toFixed(1));
