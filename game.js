// RAD DRIFT host: boots the no-libc Zig/WASM game, feeds input, blits pixels, synth SFX.
(() => {
  const canvas = document.getElementById("c");
  const ctx = canvas.getContext("2d", { alpha: false });
  const W = 480, H = 270;
  const img = ctx.createImageData(W, H);

  let X = null, ready = false;

  // ---------------- audio (procedural, no samples) ----------------
  const Audio = {
    ac: null, on: true, master: null,
    init() {
      if (this.ac) return;
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.ac = new AC();
      this.master = this.ac.createGain();
      this.master.gain.value = 0.34;
      this.master.connect(this.ac.destination);
    },
    resume() { this.init(); if (this.ac && this.ac.state === "suspended") this.ac.resume(); },
    noiseBuf(sec) {
      const n = Math.floor(this.ac.sampleRate * sec);
      const b = this.ac.createBuffer(1, n, this.ac.sampleRate);
      const d = b.getChannelData(0);
      for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
      return b;
    },
    tone(freq, dur, type, gain, slideTo) {
      if (!this.on || !this.ac) return;
      const t = this.ac.currentTime;
      const o = this.ac.createOscillator();
      const g = this.ac.createGain();
      o.type = type || "square";
      o.frequency.setValueAtTime(freq, t);
      if (slideTo) o.frequency.exponentialRampToValueAtTime(Math.max(20, slideTo), t + dur);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain, t + 0.006);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(this.master);
      o.start(t); o.stop(t + dur + 0.02);
    },
    noise(dur, gain, hp, lp) {
      if (!this.on || !this.ac) return;
      const t = this.ac.currentTime;
      const s = this.ac.createBufferSource();
      s.buffer = this.noiseBuf(Math.max(0.02, dur));
      const g = this.ac.createGain();
      const f1 = this.ac.createBiquadFilter();
      f1.type = "highpass"; f1.frequency.value = hp || 200;
      const f2 = this.ac.createBiquadFilter();
      f2.type = "lowpass"; f2.frequency.value = lp || 6000;
      g.gain.setValueAtTime(gain, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      s.connect(f1); f1.connect(f2); f2.connect(g); g.connect(this.master);
      s.start(t); s.stop(t + dur + 0.02);
    },
    shoot() { this.tone(880 + Math.random()*160, 0.07, "square", 0.10, 300); },
    hit()   { this.noise(0.05, 0.10, 900, 7000); },
    kill()  { this.tone(300, 0.13, "triangle", 0.13, 90); this.noise(0.12, 0.12, 200, 4000); },
    hurt()  { this.tone(150, 0.22, "sawtooth", 0.22, 60); },
    boom()  { this.noise(0.45, 0.3, 60, 2200); this.tone(70, 0.4, "sine", 0.2, 35); },
    level() { [523,659,784,1046].forEach((f,i)=>setTimeout(()=>this.tone(f,0.16,"triangle",0.16), i*70)); },
  };

  // ---------------- music: pulsing bass + drums, intensifies with wave ----------------
  const Music = {
    ac: null, step: 0, next: 0, timer: null, intensity: 0,
    start(ac) {
      this.ac = ac;
      if (this.timer) return;
      const bpm = 132, spb = 60 / bpm / 2; // 8th notes
      this.next = ac.currentTime + 0.1;
      this.timer = setInterval(() => {
        if (!ac || !Audio.on) return;
        while (this.next < ac.currentTime + 0.25) {
          this.schedule(this.step, this.next, spb);
          this.step = (this.step + 1) % 16;
          this.next += spb;
        }
      }, 40);
    },
    I() {
      // intensity 0..1 from game time
      let v = 0;
      try { v = Math.min(1, X.dbg_time() / 120); } catch(e){}
      return v;
    },
    bass(f, t, dur, gain) {
      const ac = this.ac;
      const o = ac.createOscillator(), g = ac.createGain(), f1 = ac.createBiquadFilter();
      o.type = "sawtooth"; o.frequency.value = f;
      f1.type = "lowpass"; f1.frequency.value = 220 + this.I() * 900; f1.Q.value = 6;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain, t + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(f1); f1.connect(g); g.connect(Audio.master);
      o.start(t); o.stop(t + dur + 0.02);
    },
    kick(t) {
      const ac = this.ac;
      const o = ac.createOscillator(), g = ac.createGain();
      o.type = "sine";
      o.frequency.setValueAtTime(150, t);
      o.frequency.exponentialRampToValueAtTime(45, t + 0.12);
      g.gain.setValueAtTime(0.5, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16);
      o.connect(g); g.connect(Audio.master);
      o.start(t); o.stop(t + 0.18);
    },
    hat(t, open) {
      const ac = this.ac;
      const s = ac.createBufferSource();
      s.buffer = Audio.noiseBuf(0.05);
      const f = ac.createBiquadFilter(); f.type = "highpass"; f.frequency.value = 7000;
      const g = ac.createGain();
      const d = open ? 0.12 : 0.04;
      g.gain.setValueAtTime(open ? 0.12 : 0.07, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + d);
      s.connect(f); f.connect(g); g.connect(Audio.master);
      s.start(t); s.stop(t + d + 0.02);
    },
    schedule(step, t, spb) {
      const i = this.I();
      // bassline (A minor-ish groove)
      const notes = [55, 55, 82.4, 55, 65.4, 55, 73.4, 82.4];
      if (step % 2 === 0) {
        const n = notes[(step / 2) % 8];
        this.bass(n, t, spb * 1.7, 0.16 + i * 0.12);
      }
      if (step % 4 === 0) this.kick(t);
      if (step % 8 === 4) this.kick(t);
      if (step % 2 === 1) this.hat(t, step % 4 === 3);
      if (i > 0.5 && step % 4 === 2) this.bass(notes[step % 8] * 2, t, spb, 0.05 * i);
    },
  };

  // ---------------- event polling -> sfx ----------------
  let evLast = { s:0, h:0, k:0, u:0, b:0, l:0 };
  function pollEvents() {
    if (!X || !Audio.ac) return;
    const s = X.ev(0), h = X.ev(1), k = X.ev(2), u = X.ev(3), b = X.ev(4), l = X.ev(5);
    const ns = s - evLast.s, nh = h - evLast.h, nk = k - evLast.k, nu = u - evLast.u,
          nb = b - evLast.b, nl = l - evLast.l;
    if (ns > 0) Audio.shoot();
    if (nh > 0) Audio.hit();
    if (nk > 0) Audio.kill();
    if (nu > 0) Audio.hurt();
    if (nb > 0) Audio.boom();
    if (nl > 0) Audio.level();
    evLast = { s, h, k, u, b, l };
  }

  // ---------------- input ----------------
  const forward = new Set([32, 37, 38, 39, 40, 13]);
  addEventListener("keydown", (e) => {
    if (forward.has(e.keyCode)) e.preventDefault();
    if (!ready) return;
    X.key(e.keyCode >>> 0, 1);
    Audio.resume();
  });
  addEventListener("keyup", (e) => {
    if (forward.has(e.keyCode)) e.preventDefault();
    if (!ready) return;
    X.key(e.keyCode >>> 0, 0);
  });
  function mapMouse(e) {
    const r = canvas.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width * W;
    const y = (e.clientY - r.top) / r.height * H;
    X.mousemove(x, y);
  }
  canvas.addEventListener("mousemove", (e) => ready && mapMouse(e));
  canvas.addEventListener("mousedown", (e) => { if (!ready) return; mapMouse(e); X.mousedown(1); Audio.resume(); });
  canvas.addEventListener("mouseup", () => ready && X.mousedown(0));
  canvas.addEventListener("touchstart", (e) => {
    if (!ready) return; e.preventDefault();
    const t = e.touches[0]; const r = canvas.getBoundingClientRect();
    X.mousemove((t.clientX-r.left)/r.width*W, (t.clientY-r.top)/r.height*H);
    X.mousedown(1); Audio.resume();
  }, { passive: false });
  canvas.addEventListener("touchend", (e) => { e.preventDefault(); if (ready) X.mousedown(0); }, { passive:false });

  document.getElementById("mute").onclick = (e) => {
    Audio.on = !Audio.on;
    if (Audio.master) Audio.master.gain.value = Audio.on ? 0.34 : 0;
    e.target.textContent = "sound: " + (Audio.on ? "on" : "off");
  };
  document.getElementById("full").onclick = () => {
    const el = document.querySelector(".stage");
    if (document.fullscreenElement) document.exitFullscreen();
    else el.requestFullscreen && el.requestFullscreen();
  };

  // ---------------- boot + loop ----------------
  fetch("raddrift.wasm").then(r => r.arrayBuffer()).then(bytes => {
    return WebAssembly.instantiate(bytes, {}).then(res => {
      X = (res.instance || res).exports;
      X.init((Math.random() * 0xffffffff) >>> 0);
      window.__rd = X; // debug/test handle
      ready = true;
      Audio.resume();
      if (Audio.ac) Music.start(Audio.ac);
      requestAnimationFrame(loop);
    });
  }).catch(err => {
    ctx.fillStyle = "#200"; ctx.fillRect(0,0,W,H);
    ctx.fillStyle = "#f88"; ctx.font = "12px monospace";
    ctx.fillText("wasm load failed: " + err, 10, 40);
  });

  let last = performance.now();
  function loop(t) {
    const dt = Math.min(50, t - last);
    last = t;
    X.frame(dt);
    const px = new Uint8ClampedArray(X.memory.buffer, X.fbptr(), W * H * 4);
    img.data.set(px);
    ctx.putImageData(img, 0, 0);
    pollEvents();
    requestAnimationFrame(loop);
  }
})();
