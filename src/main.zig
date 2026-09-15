// ============================================================================
//  RAD DRIFT  --  a freestanding (no libc, no std) WASM roguelite arena shooter
//  build: zig build-exe src/main.zig -target wasm32-freestanding -O ReleaseFast
//         -fno-entry -rdynamic
// ============================================================================
const font = @import("font.zig");

// ---------------------------------------------------------------- dimensions
const W: i32 = 480; // logical pixels
const H: i32 = 270;
const WU: usize = 480;
const HU: usize = 270;
const FBSZ: usize = WU * HU * 4;

var fb: [FBSZ]u8 = undefined;

// screen shake, applied at raster time
var shx: f32 = 0;
var shy: f32 = 0;

// ---------------------------------------------------------------------- math
inline fn clampf(v: f32, lo: f32, hi: f32) f32 {
    return if (v < lo) lo else if (v > hi) hi else v;
}
inline fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
inline fn dist2(ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const dx = bx - ax;
    const dy = by - ay;
    return dx * dx + dy * dy;
}
inline fn len2(x: f32, y: f32) f32 {
    return x * x + y * y;
}
const PI: f32 = 3.14159265358979;
// degree-9 odd minimax polynomial, |x|<=1  (accurate to ~1e-6)
inline fn atanP(x: f32) f32 {
    const x2 = x * x;
    var p: f32 = 0.0208351;
    p = p * x2 - 0.0851330;
    p = p * x2 + 0.1801410;
    p = p * x2 - 0.3302995;
    p = p * x2 + 0.9998660;
    return p * x;
}
inline fn atan2(y: f32, x: f32) f32 {
    if (x == 0) {
        if (y > 0) return PI / 2;
        if (y < 0) return -PI / 2;
        return 0;
    }
    const ax = @abs(x);
    const ay = @abs(y);
    var a: f32 = undefined;
    if (ax >= ay) {
        a = atanP(ay / ax);
    } else {
        a = PI / 2 - atanP(ax / ay);
    }
    if (x < 0) a = PI - a;
    if (y < 0) a = -a;
    return a;
}

// ----------------------------------------------------------------------- rng
var rng_state: u32 = 0x9e3779b9;
fn rndSeed(s: u32) void {
    rng_state = if (s == 0) 0x12345678 else s;
}
fn rndU32() u32 {
    // xorshift32
    var x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
}
fn rnd() f32 {
    return @as(f32, @floatFromInt(rndU32() >> 8)) / 16777216.0;
}
fn rndRange(a: f32, b: f32) f32 {
    return a + (b - a) * rnd();
}
fn rndi(n: i32) i32 {
    if (n <= 1) return 0;
    return @intCast(rndU32() % @as(u32, @intCast(n)));
}

// ------------------------------------------------------------------ color util
inline fn cr(c: u32) u8 { return @intCast((c >> 16) & 0xff); }
inline fn cg(c: u32) u8 { return @intCast((c >> 8) & 0xff); }
inline fn cb(c: u32) u8 { return @intCast(c & 0xff); }

inline fn addSat(a: u8, b: u8) u8 {
    const s: u16 = @as(u16, a) + @as(u16, b);
    return if (s > 255) 255 else @intCast(s);
}

// ------------------------------------------------------------- raster helpers
inline fn put(x: i32, y: i32, r: u8, g: u8, b: u8) void {
    if (x < 0 or y < 0 or x >= W or y >= H) return;
    const i: usize = (@as(usize, @intCast(y)) * WU + @as(usize, @intCast(x))) * 4;
    fb[i] = addSat(fb[i], r);
    fb[i + 1] = addSat(fb[i + 1], g);
    fb[i + 2] = addSat(fb[i + 2], b);
    fb[i + 3] = 255;
}

fn clearBuf(r: u8, g: u8, b: u8) void {
    var i: usize = 0;
    while (i < FBSZ) : (i += 4) {
        fb[i] = r;
        fb[i + 1] = g;
        fb[i + 2] = b;
        fb[i + 3] = 255;
    }
}

// soft additive glow disc (neon look)
fn glow(cx: f32, cy: f32, rad: f32, col: u32, gain: f32) void {
    if (rad <= 0) return;
    const gx = cx + shx;
    const gy = cy + shy;
    const rf: f32 = @floatFromInt(cr(col));
    const gf: f32 = @floatFromInt(cg(col));
    const bf: f32 = @floatFromInt(cb(col));
    const x0: i32 = @intFromFloat(@floor(gx - rad));
    const x1: i32 = @intFromFloat(@ceil(gx + rad));
    const y0: i32 = @intFromFloat(@floor(gy - rad));
    const y1: i32 = @intFromFloat(@ceil(gy + rad));
    const r2 = rad * rad;
    var y = y0;
    while (y <= y1) : (y += 1) {
        const dy = @as(f32, @floatFromInt(y)) + 0.5 - gy;
        var x = x0;
        while (x <= x1) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - gx;
            const d2 = dx * dx + dy * dy;
            if (d2 <= r2) {
                const d = @sqrt(d2);
                const a = 1.0 - d / rad;
                const s = a * a * gain;
                if (s > 0.004) {
                    put(x, y, @intFromFloat(clampf(rf * s, 0, 255)), @intFromFloat(clampf(gf * s, 0, 255)), @intFromFloat(clampf(bf * s, 0, 255)));
                }
            }
        }
    }
}

// crisp orb: solid core + 1px soft edge
fn orb(cx: f32, cy: f32, rad: f32, col: u32, gain: f32) void {
    if (rad <= 0) return;
    const gx = cx + shx;
    const gy = cy + shy;
    const rf: f32 = @floatFromInt(cr(col));
    const gf: f32 = @floatFromInt(cg(col));
    const bf: f32 = @floatFromInt(cb(col));
    const x0: i32 = @intFromFloat(@floor(gx - rad - 1));
    const x1: i32 = @intFromFloat(@ceil(gx + rad + 1));
    const y0: i32 = @intFromFloat(@floor(gy - rad - 1));
    const y1: i32 = @intFromFloat(@ceil(gy + rad + 1));
    var y = y0;
    while (y <= y1) : (y += 1) {
        const dy = @as(f32, @floatFromInt(y)) + 0.5 - gy;
        var x = x0;
        while (x <= x1) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - gx;
            const d = @sqrt(dx * dx + dy * dy);
            if (d <= rad + 1.0) {
                var a = (rad + 0.6 - d);
                a = clampf(a, 0, 1);
                const s = a * gain;
                if (s > 0.004) {
                    put(x, y, @intFromFloat(clampf(rf * s, 0, 255)), @intFromFloat(clampf(gf * s, 0, 255)), @intFromFloat(clampf(bf * s, 0, 255)));
                }
            }
        }
    }
}

// hollow ring
fn ring(cx: f32, cy: f32, rad: f32, thick: f32, col: u32, gain: f32) void {
    const gx = cx + shx;
    const gy = cy + shy;
    const rf: f32 = @floatFromInt(cr(col));
    const gf: f32 = @floatFromInt(cg(col));
    const bf: f32 = @floatFromInt(cb(col));
    const ro = rad + thick;
    const ri = rad - thick;
    const x0: i32 = @intFromFloat(@floor(gx - ro - 1));
    const x1: i32 = @intFromFloat(@ceil(gx + ro + 1));
    const y0: i32 = @intFromFloat(@floor(gy - ro - 1));
    const y1: i32 = @intFromFloat(@ceil(gy + ro + 1));
    var y = y0;
    while (y <= y1) : (y += 1) {
        const dy = @as(f32, @floatFromInt(y)) + 0.5 - gy;
        var x = x0;
        while (x <= x1) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - gx;
            const d = @sqrt(dx * dx + dy * dy);
            if (d <= ro + 1.0 and d >= ri - 1.0) {
                var a = thick + 0.6 - @abs(d - rad);
                a = clampf(a, 0, 1);
                const s = a * gain;
                if (s > 0.004) put(x, y, @intFromFloat(clampf(rf * s, 0, 255)), @intFromFloat(clampf(gf * s, 0, 255)), @intFromFloat(clampf(bf * s, 0, 255)));
            }
        }
    }
}

// thick additive line segment
fn lineSeg(ax: f32, ay: f32, bx: f32, by: f32, thick: f32, col: u32, gain: f32) void {
    const dx = bx - ax;
    const dy = by - ay;
    const steps: i32 = @intFromFloat(@max(@abs(dx), @abs(dy)) / 0.5 + 1);
    var i: i32 = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        glow(ax + dx * t, ay + dy * t, thick, col, gain);
    }
}

// filled rectangle (additive)
fn rectAdd(x0: i32, y0: i32, w: i32, h: i32, col: u32, gain: f32) void {
    const rf: f32 = @floatFromInt(cr(col));
    const gf: f32 = @floatFromInt(cg(col));
    const bf: f32 = @floatFromInt(cb(col));
    var y = y0;
    while (y < y0 + h) : (y += 1) {
        var x = x0;
        while (x < x0 + w) : (x += 1) {
            put(x, y, @intFromFloat(clampf(rf * gain, 0, 255)), @intFromFloat(clampf(gf * gain, 0, 255)), @intFromFloat(clampf(bf * gain, 0, 255)));
        }
    }
}

// ---------------------------------------------------------------------- text
fn textWidth(s: []const u8, scale: i32) i32 {
    if (s.len == 0) return 0;
    return @as(i32, @intCast(s.len)) * 6 * scale - scale;
}

fn drawText(x0: i32, y0: i32, s: []const u8, scale: i32, col: u32, gain: f32) void {
    var cx: i32 = 0;
    for (s) |ch| {
        if (ch == '\n') continue;
        const idx = if (ch >= 32 and ch < 127) @as(usize, ch - 32) else 0;
        const glyph = font.font5x7[idx];
        for (0..7) |row| {
            const bits = glyph[row];
            for (0..5) |colb| {
                if ((bits >> @intCast(colb)) & 1 == 1) {
                    rectAdd(x0 + cx + @as(i32, @intCast(colb)) * scale, y0 + @as(i32, @intCast(row)) * scale, scale, scale, col, gain);
                }
            }
        }
        cx += 6 * scale;
    }
}

fn drawTextCentered(cx: i32, y0: i32, s: []const u8, scale: i32, col: u32, gain: f32) void {
    drawText(cx - @divTrunc(textWidth(s, scale), 2), y0, s, scale, col, gain);
}

// ============================================================================
//  ENTITIES
// ============================================================================
const MAXB: usize = 2048; // bullets (player + enemy)
const MAXE: usize = 320;  // enemies
const MAXP: usize = 1600; // particles
const MAXC: usize = 400;  // xp crystals

const Bullet = struct {
    on: bool = false,
    x: f32 = 0, y: f32 = 0,
    vx: f32 = 0, vy: f32 = 0,
    life: f32 = 0,
    dmg: f32 = 0,
    rad: f32 = 2,
    pierce: i32 = 0,
    enemy: bool = false,
    homing: f32 = 0,
    col: u32 = 0xffffff,
    crit: bool = false,
    expl: f32 = 0,
    knock: f32 = 0,
};

const Enemy = struct {
    on: bool = false,
    x: f32 = 0, y: f32 = 0,
    vx: f32 = 0, vy: f32 = 0,
    hp: f32 = 0, maxhp: f32 = 1,
    rad: f32 = 7,
    kind: u8 = 0,
    fire_cd: f32 = 0,
    touch_cd: f32 = 0,
    flash: f32 = 0,
    slow: f32 = 0,
    anim: f32 = 0,
    value: f32 = 1,
    dash_id: i32 = -1,
    fuse: f32 = 0,
    spawn_t: f32 = 0, // spawn-in telegraph timer
};

const Particle = struct {
    on: bool = false,
    x: f32 = 0, y: f32 = 0,
    vx: f32 = 0, vy: f32 = 0,
    life: f32 = 0, maxlife: f32 = 1,
    rad: f32 = 1,
    col: u32 = 0xffffff,
    drag: f32 = 2.0,
};

const Crystal = struct {
    on: bool = false,
    x: f32 = 0, y: f32 = 0,
    vx: f32 = 0, vy: f32 = 0,
    val: f32 = 1,
    life: f32 = 18,
};

var bullets: [MAXB]Bullet = [_]Bullet{.{}} ** MAXB;
var enemies: [MAXE]Enemy = [_]Enemy{.{}} ** MAXE;
var parts: [MAXP]Particle = [_]Particle{.{}} ** MAXP;
var crystals: [MAXC]Crystal = [_]Crystal{.{}} ** MAXC;

// ------------------------------------------------------------------ palette
const C_BG: u32 = 0x05060b;
const C_PLAYER: u32 = 0x66f0ff;
const C_WHITE: u32 = 0xfff4e0;
const C_XP: u32 = 0x9d7dff;
const C_EBULLET: u32 = 0xff6a3a;
const C_HP: u32 = 0x5dff9b;
const TITLE_PAL = [_]u32{ 0xff4d6d, 0xffb84d, 0x66f0ff, 0x9d7dff };

// ------------------------------------------------------------- player stats
var p_x: f32 = 240; var p_y: f32 = 135;
var p_vx: f32 = 0;  var p_vy: f32 = 0;
var p_hp: f32 = 100; var p_maxhp: f32 = 100;
var p_r: f32 = 7;
var p_aimx: f32 = 1; var p_aimy: f32 = 0;
var p_facing: f32 = 1;

var s_dmg: f32 = 9;
var s_fire: f32 = 0.30;
var s_bspeed: f32 = 320;
var s_bsize: f32 = 2.6;
var s_multi: i32 = 1;
var s_spread: f32 = 0.18;
var s_pierce: i32 = 0;
var s_crit: f32 = 0.05;
var s_critm: f32 = 2.2;
var s_homing: f32 = 0;
var s_knock: f32 = 160;
var s_lifesteal: f32 = 0;
var s_expl: f32 = 0;
var s_speed: f32 = 108;
var s_dashcd: f32 = 1.3;
var s_dashdmg: f32 = 22;
var s_regen: f32 = 0;
var s_magnet: f32 = 58;
var s_xpm: f32 = 1;
var s_thorns: f32 = 0;
var s_armor: f32 = 0;

var dash_t: f32 = 0;
var dash_cd: f32 = 0;
var dash_idx: i32 = 0;
var dash_dx: f32 = 0;
var dash_dy: f32 = 0;
var invul: f32 = 0;
var fire_t: f32 = 0;
var muzzle: f32 = 0;
var heat: f32 = 0;
var overheat: f32 = 0;
var hurt_t: f32 = 0;
var regen_acc: f32 = 0;
var calm_t: f32 = 0; // time since last hit (out-of-combat regen)

// ------------------------------------------------------------------- game
var state: u8 = 0; // 0 title 1 play 2 levelup 3 dead
var g_time: f32 = 0;
var g_score: f32 = 0;
var g_xp: f32 = 0;
var g_level: i32 = 1;
var g_xpnext: f32 = 6;
var combo: i32 = 0;
var combo_t: f32 = 0;
var kills: i32 = 0;
var wave: i32 = 1;
var wave_t: f32 = 0;
var spawn_t: f32 = 1.0;
var shake: f32 = 0;
var hitstop: f32 = 0;
var banner: f32 = 0;
var banner_txt: []const u8 = "";
var boss_alive: bool = false;
var flash_white: f32 = 0;

var cards_active: bool = false;
var card_choices: [3]usize = .{ 0, 0, 0 };

var mouse_x: f32 = 240;
var mouse_y: f32 = 135;
var mouse_down: bool = false;

const KW: u32 = 87; const KA: u32 = 65; const KS: u32 = 83; const KD: u32 = 68;
const KSPACE: u32 = 32; const KENTER: u32 = 13; const KR: u32 = 82;
const KSHIFT: u32 = 16; const KP: u32 = 80;
const KUP: u32 = 38; const KDOWN: u32 = 40; const KLEFT: u32 = 37; const KRIGHT: u32 = 39;
const K1: u32 = 49; const K2: u32 = 50; const K3: u32 = 51;

var keys: u32 = 0; // held movement bits

// audio event counters (polled by the host)
var ev_shoot: i32 = 0;
var ev_hit: i32 = 0;
var ev_kill: i32 = 0;
var ev_hurt: i32 = 0;
var ev_boom: i32 = 0;
var ev_level: i32 = 0;

// -------------------------------------------------------------- particles
fn burst(x: f32, y: f32, n: i32, speed: f32, col: u32, life: f32, rad: f32) void {
    var k: i32 = 0;
    while (k < n) : (k += 1) {
        var i: usize = 0;
        while (i < MAXP) : (i += 1) {
            if (!parts[i].on) {
                const a = rnd() * 6.2831853;
                const sp = speed * (0.35 + rnd() * 0.9);
                parts[i] = .{
                    .on = true, .x = x, .y = y,
                    .vx = @cos(a) * sp, .vy = @sin(a) * sp,
                    .life = life * (0.6 + rnd() * 0.7), .maxlife = life,
                    .rad = rad * (0.6 + rnd() * 0.9), .col = col,
                };
                break;
            }
        }
    }
}

fn spawnCrystal(x: f32, y: f32, val: f32) void {
    var i: usize = 0;
    while (i < MAXC) : (i += 1) {
        if (!crystals[i].on) {
            crystals[i] = .{ .on = true, .x = x, .y = y, .val = val, .life = 18 };
            return;
        }
    }
}

fn freeBullet() ?*Bullet {
    var i: usize = 0;
    while (i < MAXB) : (i += 1) {
        if (!bullets[i].on) return &bullets[i];
    }
    return null;
}

fn shootBullet(x: f32, y: f32, dx: f32, dy: f32, sp: f32, dmg: f32, rad: f32, enemy: bool, col: u32) void {
    const b = freeBullet() orelse return;
    b.* = .{
        .on = true, .x = x, .y = y,
        .vx = dx * sp, .vy = dy * sp,
        .life = if (enemy) 4.0 else 1.6,
        .dmg = dmg, .rad = rad, .enemy = enemy, .col = col,
        .pierce = if (enemy) 0 else s_pierce,
        .homing = if (enemy) 0 else s_homing,
        .expl = if (enemy) 0 else s_expl,
        .knock = if (enemy) 0 else s_knock,
    };
}

// ------------------------------------------------------------- enemy spawn
fn findEnemySlot() ?*Enemy {
    var i: usize = 0;
    while (i < MAXE) : (i += 1) {
        if (!enemies[i].on) return &enemies[i];
    }
    return null;
}

fn spawnEnemyAt(kind: u8, x: f32, y: f32, scale: f32) void {
    const e = findEnemySlot() orelse return;
    var hp: f32 = 18;
    var rad: f32 = 7;
    var val: f32 = 1;
    switch (kind) {
        0 => { hp = 18; rad = 7; val = 1; },
        1 => { hp = 13; rad = 7; val = 1.4; },
        2 => { hp = 80; rad = 13; val = 3; },
        3 => { hp = 12; rad = 7; val = 1.2; },
        4 => { hp = 30; rad = 10; val = 2; },
        5 => { hp = 700; rad = 26; val = 25; },
        else => {},
    }
    hp *= scale;
    if (kind == 5) hp *= 1.0 + @as(f32, @floatFromInt(wave)) * 0.15;
    e.* = .{
        .on = true, .x = x, .y = y, .hp = hp, .maxhp = hp, .rad = rad,
        .kind = kind, .value = val, .spawn_t = if (kind == 5) 0.6 else 0.0,
        .fire_cd = rndRange(0.5, 2.0),
    };
}

fn spawnEnemyEdge(kind: u8, scale: f32) void {
    const m: f32 = 14;
    const side = rndi(4);
    var x: f32 = 0; var y: f32 = 0;
    if (side == 0) { x = rndRange(m, 480 - m); y = -6; }
    else if (side == 1) { x = rndRange(m, 480 - m); y = 276; }
    else if (side == 2) { x = -6; y = rndRange(m, 270 - m); }
    else { x = 486; y = rndRange(m, 270 - m); }
    spawnEnemyAt(kind, x, y, scale);
}

fn pickEnemyKind() u8 {
    const t = g_time;
    const r = rnd();
    if (t < 12) {
        return if (r < 0.8) 0 else 1;
    } else if (t < 30) {
        if (r < 0.5) return 0;
        if (r < 0.75) return 1;
        if (r < 0.9) return 3;
        return 4;
    } else {
        if (r < 0.34) return 0;
        if (r < 0.55) return 1;
        if (r < 0.72) return 3;
        if (r < 0.86) return 4;
        return 2;
    }
}

// ---------------------------------------------------------------- upgrades
fn upDmg() void { s_dmg *= 1.28; }
fn upFire() void { s_fire = @max(0.07, s_fire * 0.83); }
fn upMulti() void { s_multi += 1; s_spread += 0.05; }
fn upPierce() void { s_pierce += 1; s_dmg *= 0.95; }
fn upCrit() void { s_crit = @min(0.85, s_crit + 0.09); }
fn upCritM() void { s_critm += 0.6; s_crit += 0.03; }
fn upBig() void { s_bsize *= 1.35; s_dmg *= 1.12; }
fn upHoming() void { s_homing += 0.55; s_bspeed *= 0.95; }
fn upLifesteal() void { s_lifesteal += 0.5; }
fn upVitality() void { p_maxhp += 25; p_hp = @min(p_maxhp, p_hp + 25); }
fn upRegen() void { s_regen += 0.9; }
fn upSpeed() void { s_speed *= 1.12; }
fn upDash() void { s_dashcd *= 0.75; s_dashdmg += 14; s_regen += 0.2; }
fn upMagnet() void { s_magnet += 45; s_xpm += 0.18; }
fn upThorns() void { s_thorns += 16; }
fn upExpl() void { s_expl += 16; }
fn upKnock() void { s_knock += 140; s_dmg *= 1.05; }
fn upArmor() void { s_armor += 0.12; s_speed *= 0.98; }
fn upBulletSpeed() void { s_bspeed *= 1.22; }
fn upHPNow() void { p_hp = @min(p_maxhp, p_hp + 40); }
fn upFrenzy() void { s_fire = @max(0.06, s_fire * 0.9); s_dmg *= 0.96; }

const Upgrade = struct {
    name: []const u8,
    desc: []const u8,
    col: u32,
    weight: u32,
    apply: *const fn () void,
};

const R_COMMON: u32 = 0x8fd9ff;
const R_RARE: u32 = 0xc98dff;
const R_EPIC: u32 = 0xffc14d;

const upgrades = [_]Upgrade{
    .{ .name = "SHARPSHOOTER", .desc = "+28% DAMAGE", .col = R_COMMON, .weight = 100, .apply = upDmg },
    .{ .name = "RAPID FIRE", .desc = "-17% FIRE COOLDOWN", .col = R_COMMON, .weight = 100, .apply = upFire },
    .{ .name = "MULTISHOT", .desc = "+1 PROJECTILE", .col = R_EPIC, .weight = 34, .apply = upMulti },
    .{ .name = "PIERCE", .desc = "SHOTS PIERCE +1 ENEMY", .col = R_RARE, .weight = 60, .apply = upPierce },
    .{ .name = "CRITICAL", .desc = "+9% CRIT CHANCE", .col = R_COMMON, .weight = 90, .apply = upCrit },
    .{ .name = "DEADEYE", .desc = "+0.6x CRIT DAMAGE", .col = R_RARE, .weight = 60, .apply = upCritM },
    .{ .name = "BIG ROUNDS", .desc = "+35% BULLET SIZE, +12% DMG", .col = R_COMMON, .weight = 85, .apply = upBig },
    .{ .name = "SEEKER", .desc = "SHOTS HOMING", .col = R_RARE, .weight = 55, .apply = upHoming },
    .{ .name = "LEECH", .desc = "+0.5 HP PER KILL", .col = R_RARE, .weight = 55, .apply = upLifesteal },
    .{ .name = "VITALITY", .desc = "+25 MAX HP & HEAL", .col = R_COMMON, .weight = 95, .apply = upVitality },
    .{ .name = "REGEN", .desc = "+0.9 HP / SEC", .col = R_RARE, .weight = 55, .apply = upRegen },
    .{ .name = "FLEET", .desc = "+12% MOVE SPEED", .col = R_COMMON, .weight = 85, .apply = upSpeed },
    .{ .name = "PHASE DASH", .desc = "-25% DASH CD, +DMG", .col = R_RARE, .weight = 60, .apply = upDash },
    .{ .name = "MAGNET", .desc = "+45 PICKUP RANGE, +XP", .col = R_COMMON, .weight = 80, .apply = upMagnet },
    .{ .name = "THORNS", .desc = "DAMAGE AURA NEARBY", .col = R_RARE, .weight = 50, .apply = upThorns },
    .{ .name = "VOLATILE", .desc = "+EXPLOSIVE HITS", .col = R_EPIC, .weight = 30, .apply = upExpl },
    .{ .name = "MOMENTUM", .desc = "+KNOCKBACK, +5% DMG", .col = R_COMMON, .weight = 70, .apply = upKnock },
    .{ .name = "PLATING", .desc = "+12% ARMOR", .col = R_RARE, .weight = 55, .apply = upArmor },
    .{ .name = "OVERCLOCK", .desc = "+22% BULLET SPEED", .col = R_COMMON, .weight = 70, .apply = upBulletSpeed },
    .{ .name = "FIELD MEDIC", .desc = "HEAL 40 HP", .col = R_COMMON, .weight = 75, .apply = upHPNow },
    .{ .name = "FRENZY", .desc = "-10% CD, -4% DMG", .col = R_COMMON, .weight = 65, .apply = upFrenzy },
};

fn rollCards() void {
    var pool: [upgrades.len]usize = undefined;
    var n: usize = 0;
    for (0..upgrades.len) |i| { pool[n] = i; n += 1; }
    for (0..3) |k| {
        var total: u32 = 0;
        for (0..n) |i| total += upgrades[pool[i]].weight;
        var r = rndU32() % total;
        var pick: usize = 0;
        for (0..n) |i| {
            const w = upgrades[pool[i]].weight;
            if (r < w) { pick = i; break; }
            r -= w;
        }
        card_choices[k] = pool[pick];
        // remove pick
        var j = pick;
        while (j + 1 < n) : (j += 1) pool[j] = pool[j + 1];
        n -= 1;
    }
    cards_active = true;
}

fn applyCard(k: usize) void {
    upgrades[card_choices[k]].apply();
    cards_active = false;
    ev_shoot = 0; ev_hit = 0; ev_kill = 0; ev_hurt = 0; ev_boom = 0; ev_level = 0;
    state = 1;
}

// ------------------------------------------------------------------ combat
fn hurtEnemy(e: *Enemy, dmg: f32, crit: bool, knockx: f32, knocky: f32) void {
    if (e.spawn_t > 0.05) return;
    e.hp -= dmg;
    e.flash = 0.10;
    if (knockx != 0 or knocky != 0) {
        e.vx += knockx;
        e.vy += knocky;
    }
    hitstop = @max(hitstop, if (crit) @as(f32, 0.045) else @as(f32, 0.02));
    ev_hit += 1;
    burst(e.x, e.y, if (crit) 5 else 2, 90, if (crit) 0xffe08a else 0xff9a6a, 0.28, 1.4);
    if (e.hp <= 0) killEnemy(e);
}

fn killEnemy(e: *Enemy) void {
    if (!e.on) return;
    e.on = false;
    ev_kill += 1;
    kills += 1;
    combo += 1;
    combo_t = 2.2;
    const cmul = 1.0 + @as(f32, @floatFromInt(combo)) * 0.06;
    const sc = e.value * cmul * (1.0 + @as(f32, @floatFromInt(wave)) * 0.05);
    g_score += sc * 10.0;
    g_xp += e.value * s_xpm * cmul;
    if (s_lifesteal > 0) p_hp = @min(p_maxhp, p_hp + s_lifesteal);
    shake = @max(shake, if (e.kind == 5) @as(f32, 16.0) else @as(f32, 4.5));
    flash_white = @max(flash_white, if (e.kind == 5) @as(f32, 0.5) else @as(f32, 0.0));
    const col: u32 = switch (e.kind) {
        0 => 0xff4d6d, 1 => 0xffb84d, 2 => 0xc078ff, 3 => 0xffe666, 4 => 0x6dff8a, 5 => 0xff33cc, else => 0xffffff,
    };
    burst(e.x, e.y, if (e.kind == 5) @as(i32, 90) else @as(i32, 14), if (e.kind == 5) @as(f32, 260.0) else @as(f32, 160.0), col, if (e.kind == 5) @as(f32, 1.0) else @as(f32, 0.55), if (e.kind == 5) @as(f32, 3.5) else @as(f32, 2.0));
    if (e.kind == 5) {
        boss_alive = false;
        banner = 2.5; banner_txt = "BOSS DOWN  +BIG XP";
        var m: i32 = 0; while (m < 8) : (m += 1) spawnCrystal(e.x + rndRange(-30, 30), e.y + rndRange(-30, 30), 6);
    }
    // splitter spawns children
    if (e.kind == 4) {
        var m: i32 = 0;
        while (m < 2) : (m += 1) spawnEnemyAt(0, e.x + rndRange(-10, 10), e.y + rndRange(-10, 10), 1.0 + g_time * 0.008);
    }
    spawnCrystal(e.x, e.y, e.value);
    if (e.kind == 2) spawnCrystal(e.x, e.y, e.value);
}

fn damagePlayer(dmg: f32) void {
    if (invul > 0 or dash_t > 0) return;
    if (hurt_t > 0.25) return;
    const d = dmg * (1.0 - clampf(s_armor, 0, 0.7));
    p_hp -= d;
    calm_t = 0;
    ev_hurt += 1;
    hurt_t = 0.45;
    invul = 0.55;
    shake = @max(shake, 7);
    hitstop = @max(hitstop, 0.05);
    burst(p_x, p_y, 12, 150, 0xff5566, 0.5, 2.0);
    if (p_hp <= 0) {
        p_hp = 0;
        state = 3;
        burst(p_x, p_y, 80, 300, C_PLAYER, 1.2, 3.0);
        shake = 22;
    }
}

fn explode(x: f32, y: f32, rad: f32, dmg: f32, from_player: bool) void {
    ev_boom += 1;
    shake = @max(shake, 6);
    burst(x, y, 22, 200, 0xffb84d, 0.44, 2.4);
    ring(x, y, rad * 0.6, 2.0, 0xffc14d, 1.4);
    if (from_player) {
        for (&enemies) |*e| {
            if (e.on and dist2(x, y, e.x, e.y) < rad * rad) hurtEnemy(e, dmg, false, 0, 0);
        }
    } else {
        if (dist2(x, y, p_x, p_y) < rad * rad) damagePlayer(dmg);
    }
}

// ============================================================================
//  UPDATE
// ============================================================================
fn nearestEnemy(x: f32, y: f32, maxd: f32) ?*Enemy {
    var best: ?*Enemy = null;
    var bd = maxd * maxd;
    for (&enemies) |*e| {
        if (!e.on or e.spawn_t > 0.05) continue;
        const d = dist2(x, y, e.x, e.y);
        if (d < bd) { bd = d; best = e; }
    }
    return best;
}

fn startDash() void {
    const dx = if (keys & 1 != 0) @as(f32, -1) else if (keys & 8 != 0) @as(f32, 1) else 0;
    _ = dx;
}

fn tryDash() void {
    var dx: f32 = 0; var dy: f32 = 0;
    if (keys & 1 != 0) dy -= 1;
    if (keys & 2 != 0) dx -= 1;
    if (keys & 4 != 0) dy += 1;
    if (keys & 8 != 0) dx += 1;
    if (dx == 0 and dy == 0) { dx = p_aimx; dy = p_aimy; }
    const l = @sqrt(len2(dx, dy));
    if (l > 0.001) { dx /= l; dy /= l; }
    dash_t = 0.16;
    dash_cd = s_dashcd;
    dash_idx += 1;
    dash_dx = dx; dash_dy = dy;
    invul = @max(invul, 0.28);
    shake = @max(shake, 2.5);
    burst(p_x, p_y, 8, 90, C_PLAYER, 0.35, 1.8);
}

fn fire() void {
    // aim at nearest enemy
    if (nearestEnemy(p_x, p_y, 260)) |e| {
        const dx = e.x - p_x; const dy = e.y - p_y;
        const l = @sqrt(len2(dx, dy));
        if (l > 0.001) { p_aimx = dx / l; p_aimy = dy / l; }
    }
    const base = atan2(p_aimy, p_aimx);
    var k: i32 = 0;
    const n = s_multi;
    while (k < n) : (k += 1) {
        const off = if (n == 1) 0.0 else (@as(f32, @floatFromInt(k)) - @as(f32, @floatFromInt(n - 1)) * 0.5) * s_spread;
        const a = base + off;
        const crit = rnd() < s_crit;
        const dmg = s_dmg * (if (crit) s_critm else 1.0);
        const b = freeBullet() orelse break;
        b.* = .{
            .on = true,
            .x = p_x + @cos(a) * (p_r + 2), .y = p_y + @sin(a) * (p_r + 2),
            .vx = @cos(a) * s_bspeed, .vy = @sin(a) * s_bspeed,
            .life = 1.5, .dmg = dmg, .rad = s_bsize, .enemy = false,
            .col = if (crit) 0xffe08a else C_PLAYER,
            .pierce = s_pierce, .homing = s_homing, .crit = crit,
            .expl = s_expl, .knock = s_knock,
        };
    }
    muzzle = 0.06;
    ev_shoot += 1;
    heat += 0.085;
    if (heat >= 1.0) { heat = 1.0; overheat = 1.15; shake = @max(shake, 3); burst(p_x + p_aimx * 10, p_y + p_aimy * 10, 10, 120, 0xff7a3a, 0.4, 2.0); }
}

fn updatePlayer(dt: f32) void {
    var dx: f32 = 0; var dy: f32 = 0;
    if (keys & 1 != 0) dy -= 1;
    if (keys & 2 != 0) dx -= 1;
    if (keys & 4 != 0) dy += 1;
    if (keys & 8 != 0) dx += 1;
    const l = @sqrt(len2(dx, dy));
    if (l > 0.001) { dx /= l; dy /= l; }

    if (dash_t > 0) {
        p_vx = dash_dx * 560;
        p_vy = dash_dy * 560;
        burst(p_x, p_y, 1, 20, C_PLAYER, 0.25, 1.6);
    } else {
        const k = 1.0 - @exp(-dt * 15.0);
        p_vx = lerp(p_vx, dx * s_speed, k);
        p_vy = lerp(p_vy, dy * s_speed, k);
    }

    p_x += p_vx * dt;
    p_y += p_vy * dt;
    // clamp to arena
    p_x = clampf(p_x, 12 + p_r, 468 - p_r);
    p_y = clampf(p_y, 12 + p_r, 258 - p_r);

    // timers
    if (dash_t > 0) dash_t -= dt;
    if (dash_cd > 0) dash_cd -= dt;
    if (invul > 0) invul -= dt;
    if (hurt_t > 0) hurt_t -= dt;
    if (muzzle > 0) muzzle -= dt;
    if (overheat > 0) { overheat -= dt; heat = @max(0, heat - dt * 0.9); }
    else { heat = @max(0, heat - dt * 0.55); }

    if (keys & 16 != 0 and dash_cd <= 0 and dash_t <= 0) tryDash();

    // regen
    calm_t += dt;
    if (calm_t > 2.5) {
        regen_acc += 1.8 * dt;
        if (regen_acc >= 1.0) { const h = @floor(regen_acc); regen_acc -= h; p_hp = @min(p_maxhp, p_hp + h); }
    }
    if (s_regen > 0) {
        regen_acc += s_regen * dt;
        if (regen_acc >= 1.0) { const h = @floor(regen_acc); regen_acc -= h; p_hp = @min(p_maxhp, p_hp + h); }
    }

    // autofire
    fire_t -= dt;
    if (fire_t <= 0 and overheat <= 0) {
        if (nearestEnemy(p_x, p_y, 250)) |_| {
            fire();
            fire_t = s_fire;
        }
    }

    // thorns aura
    if (s_thorns > 0) {
        for (&enemies) |*e| {
            if (e.on and dist2(p_x, p_y, e.x, e.y) < (p_r + 34) * (p_r + 34)) {
                e.hp -= s_thorns * dt;
                e.flash = 0.05;
                if (e.hp <= 0) killEnemy(e);
            }
        }
    }
}

fn enemyFire(e: *Enemy, spread: f32, count: i32, sp: f32) void {
    const dx = p_x - e.x; const dy = p_y - e.y;
    const l = @sqrt(len2(dx, dy));
    const base = atan2(dy, dx);
    var k: i32 = 0;
    while (k < count) : (k += 1) {
        const off = if (count == 1) 0.0 else (@as(f32, @floatFromInt(k)) - @as(f32, @floatFromInt(count - 1)) * 0.5) * spread;
        const a = base + off;
        shootBullet(e.x, e.y, @cos(a), @sin(a), sp, 8 + g_time * 0.06, 3.0, true, C_EBULLET);
    }
    _ = l;
}

fn updateEnemies(dt: f32) void {
    for (&enemies) |*e| {
        if (!e.on) continue;
        e.anim += dt;
        if (e.flash > 0) e.flash -= dt;
        if (e.touch_cd > 0) e.touch_cd -= dt;
        if (e.slow > 0) e.slow -= dt;
        if (e.spawn_t > 0) { e.spawn_t -= dt; continue; }

        const dx = p_x - e.x; const dy = p_y - e.y;
        const d = @sqrt(len2(dx, dy));
        const ux = if (d > 0.001) dx / d else 0;
        const uy = if (d > 0.001) dy / d else 0;
        const smul: f32 = if (e.slow > 0) 0.45 else 1.0;

        var tx: f32 = 0; var ty: f32 = 0;
        var acc: f32 = 4.0;

        switch (e.kind) {
            0 => { tx = ux * 52 * smul; ty = uy * 52 * smul; acc = 3.0; },
            1 => {
                // strafe / keep distance
                const want: f32 = 110;
                const dir: f32 = if (d > want + 20) 1.0 else if (d < want - 20) -1.0 else 0.0;
                const perp = @sin(e.anim * 1.3) * 0.8;
                tx = (ux * dir - uy * perp) * 46 * smul;
                ty = (uy * dir + ux * perp) * 46 * smul;
                acc = 3.0;
                e.fire_cd -= dt * smul;
                if (e.fire_cd <= 0 and d < 240) {
                    e.fire_cd = 1.7 + rnd() * 0.9;
                    enemyFire(e, 0.18, 3, 150);
                }
            },
            2 => { tx = ux * 26 * smul; ty = uy * 26 * smul; acc = 1.6; },
            3 => {
                tx = ux * 78 * smul; ty = uy * 78 * smul; acc = 4.0;
                if (d < 30) {
                    e.fuse += dt;
                    if (e.fuse > 0.55) { explode(e.x, e.y, 42, 26 + g_time * 0.1, false); e.on = false; }
                } else e.fuse = @max(0, e.fuse - dt);
            },
            4 => { tx = ux * 44 * smul; ty = uy * 44 * smul; acc = 3.0; },
            5 => {
                tx = ux * 30 * smul; ty = uy * 30 * smul; acc = 1.2;
                e.fire_cd -= dt;
                if (e.fire_cd <= 0) {
                    e.fire_cd = 1.9;
                    var k: i32 = 0;
                    const n: i32 = 14;
                    const base = e.anim * 0.7;
                    while (k < n) : (k += 1) {
                        const a = base + @as(f32, @floatFromInt(k)) * 6.2831853 / @as(f32, @floatFromInt(n));
                        shootBullet(e.x + @cos(a) * e.rad, e.y + @sin(a) * e.rad, @cos(a), @sin(a), 120, 10, 3.4, true, 0xff5ac8);
                    }
                    if (rnd() < 0.5) {
                        var m: i32 = 0; while (m < 2) : (m += 1) spawnEnemyEdge(0, 1.0 + g_time * 0.01);
                    }
                }
            },
            else => {},
        }

        const k = 1.0 - @exp(-dt * acc);
        e.vx = lerp(e.vx, tx, k);
        e.vy = lerp(e.vy, ty, k);
        e.x += e.vx * dt;
        e.y += e.vy * dt;

        // contact damage
        if (e.touch_cd <= 0 and dist2(e.x, e.y, p_x, p_y) < (e.rad + p_r) * (e.rad + p_r)) {
            const cdmg: f32 = switch (e.kind) {
                0 => 9, 1 => 7, 2 => 20, 3 => 8, 4 => 12, 5 => 26, else => 8,
            };
            damagePlayer(cdmg + g_time * 0.02);
            e.touch_cd = 0.7;
            // knockback both
            e.vx = -ux * 90; e.vy = -uy * 90;
            p_vx = ux * 160; p_vy = uy * 160;
        }

        // dash-through damage
        if (dash_t > 0 and e.dash_id != dash_idx and dist2(e.x, e.y, p_x, p_y) < (e.rad + p_r + 6) * (e.rad + p_r + 6)) {
            e.dash_id = dash_idx;
            hurtEnemy(e, s_dashdmg, true, ux * s_knock, uy * s_knock);
        }

        // cull far away
        if (e.x < -80 or e.x > 560 or e.y < -80 or e.y > 350) {
            if (e.kind != 5) e.on = false;
        }
    }
}

fn updateBullets(dt: f32) void {
    for (&bullets) |*b| {
        if (!b.on) continue;
        b.life -= dt;
        if (b.life <= 0) { b.on = false; continue; }

        if (b.homing > 0 and !b.enemy) {
            if (nearestEnemy(b.x, b.y, 220)) |e| {
                const dx = e.x - b.x; const dy = e.y - b.y;
                const l = @sqrt(len2(dx, dy));
                if (l > 0.001) {
                    const sp = @sqrt(len2(b.vx, b.vy));
                    const k = 1.0 - @exp(-dt * b.homing * 6.0);
                    const nvx = lerp(b.vx, dx / l * sp, k);
                    const nvy = lerp(b.vy, dy / l * sp, k);
                    b.vx = nvx; b.vy = nvy;
                }
            }
        }

        b.x += b.vx * dt;
        b.y += b.vy * dt;

        if (b.x < -20 or b.x > 500 or b.y < -20 or b.y > 290) {
            if (!b.enemy) { b.on = false; continue; }
        }
        if (b.x < -40 or b.x > 520 or b.y < -40 or b.y > 310) { b.on = false; continue; }

        if (b.enemy) {
            if (dist2(b.x, b.y, p_x, p_y) < (b.rad + p_r) * (b.rad + p_r)) {
                damagePlayer(b.dmg);
                b.on = false;
            }
        } else {
            for (&enemies) |*e| {
                if (!e.on or e.spawn_t > 0.05) continue;
                if (dist2(b.x, b.y, e.x, e.y) < (b.rad + e.rad) * (b.rad + e.rad)) {
                    const nx = if (e.x - b.x > 0) @as(f32, 1) else @as(f32, -1);
                    const ny = if (e.y - b.y > 0) @as(f32, 1) else @as(f32, -1);
                    hurtEnemy(e, b.dmg, b.crit, nx * b.knock, ny * b.knock);
                    if (b.expl > 0) explode(b.x, b.y, b.expl, b.dmg * 0.6, true);
                    if (b.pierce > 0) { b.pierce -= 1; } else { b.on = false; break; }
                }
            }
        }
    }
}

fn updateCrystals(dt: f32) void {
    for (&crystals) |*c| {
        if (!c.on) continue;
        c.life -= dt;
        if (c.life <= 0) { c.on = false; continue; }
        const dx = p_x - c.x; const dy = p_y - c.y;
        const d2 = len2(dx, dy);
        if (d2 < s_magnet * s_magnet) {
            const d = @sqrt(d2);
            const pull: f32 = (1.0 - d / s_magnet) * 700 + 60;
            if (d > 0.001) { c.vx += dx / d * pull * dt * 3.0; c.vy += dy / d * pull * dt * 3.0; }
        }
        c.vx *= @exp(-dt * 3.0); c.vy *= @exp(-dt * 3.0);
        c.x += c.vx * dt; c.y += c.vy * dt;
        if (d2 < (p_r + 8) * (p_r + 8)) {
            c.on = false;
            g_xp += c.val * s_xpm;
            burst(c.x, c.y, 3, 60, C_XP, 0.3, 1.5);
        }
    }
}

fn updateParticles(dt: f32) void {
    for (&parts) |*p| {
        if (!p.on) continue;
        p.life -= dt;
        if (p.life <= 0) { p.on = false; continue; }
        p.vx *= @exp(-dt * p.drag); p.vy *= @exp(-dt * p.drag);
        p.x += p.vx * dt; p.y += p.vy * dt;
    }
}

fn updateSpawning(dt: f32) void {
    wave_t += dt;
    if (wave_t > 22) {
        wave_t = 0;
        wave += 1;
        banner = 1.8;
        banner_txt = if (@mod(wave, 3) == 0) "BOSS INCOMING" else "WAVE UP";
        if (@mod(wave, 3) == 0 and !boss_alive) {
            boss_alive = true;
            spawnEnemyAt(5, 240, 60, 1.0 + g_time * 0.01);
        }
    }
    spawn_t -= dt;
    if (spawn_t <= 0) {
        const interval = @max(0.30, 1.05 - g_time * 0.013);
        spawn_t = interval * (0.75 + rnd() * 0.6);
        // count active
        var cnt: i32 = 0;
        for (&enemies) |*e| { if (e.on) cnt += 1; }
        const cap: i32 = 40 + @as(i32, @intFromFloat(g_time * 0.6));
        if (cnt < @min(cap, 140)) {
            spawnEnemyEdge(pickEnemyKind(), 1.0 + g_time * 0.012);
        }
    }
}

fn updateCards(dt: f32) void {
    _ = dt;
}

fn updateGame(dt: f32) void {
    g_time += dt;
    if (shake > 0) shake = @max(0, shake - dt * 26);
    if (banner > 0) banner -= dt;
    if (flash_white > 0) flash_white = @max(0, flash_white - dt * 4.0);
    if (combo_t > 0) { combo_t -= dt; if (combo_t <= 0) combo = 0; }

    updatePlayer(dt);
    updateEnemies(dt);
    updateBullets(dt);
    updateCrystals(dt);
    updateParticles(dt);
    updateSpawning(dt);

    if (g_xp >= g_xpnext) {
        g_xp -= g_xpnext;
        g_level += 1;
        g_xpnext = 6 + @as(f32, @floatFromInt(g_level)) * 3.6 + @as(f32, @floatFromInt(g_level * g_level)) * 0.55;
        state = 2;
        ev_level += 1;
        rollCards();
    }
}

// ============================================================================
//  RENDER
// ============================================================================
fn drawGrid() void {
    var x: i32 = 0;
    while (x <= W) : (x += 40) {
        var y: i32 = 0;
        while (y <= H) : (y += 40) { put(x, y, 12, 16, 26); }
    }
}

fn drawBar(x: i32, y: i32, w: i32, h: i32, frac: f32, col: u32) void {
    // frame
    rectAdd(x - 1, y - 1, w + 2, h + 2, 0x18202e, 1.0);
    const fillw: i32 = @intFromFloat(clampf(frac, 0, 1) * @as(f32, @floatFromInt(w)));
    if (fillw > 0) rectAdd(x, y, fillw, h, col, 1.0);
}

fn renderEnemy(e: *Enemy) void {
    const col: u32 = switch (e.kind) {
        0 => 0xff4d6d, 1 => 0xffb84d, 2 => 0xc078ff, 3 => 0xffe666, 4 => 0x6dff8a, 5 => 0xff33cc, else => 0xffffff,
    };
    if (e.spawn_t > 0) {
        ring(e.x, e.y, e.rad + e.spawn_t * 30, 1.5, col, 1.0);
        return;
    }
    const flashg: f32 = 1.0 + e.flash * 8.0;
    glow(e.x, e.y, e.rad * 1.7, col, 0.32);
    orb(e.x, e.y, e.rad, col, flashg);
    orb(e.x, e.y, e.rad * 0.45, 0xffffff, 0.5 * flashg);
    ring(e.x, e.y, e.rad, 1.0, col, 0.9);
    // eyes direction
    const dx = p_x - e.x; const dy = p_y - e.y;
    const l = @sqrt(len2(dx, dy));
    if (l > 0.001) orb(e.x + dx / l * e.rad * 0.4, e.y + dy / l * e.rad * 0.4, e.rad * 0.22, 0x110008, 1.0);
    if (e.kind == 2 or e.kind == 5) {
        const bw: i32 = if (e.kind == 5) 90 else 28;
        const bx: i32 = @intFromFloat(e.x - @as(f32, @floatFromInt(bw)) * 0.5);
        const by: i32 = @intFromFloat(e.y - e.rad - 8);
        drawBar(bx, by, bw, 3, e.hp / e.maxhp, if (e.kind == 5) 0xff33cc else 0xc078ff);
    }
}

fn renderPlayer() void {
    // dash trail
    if (dash_t > 0) {
        var k: i32 = 1;
        while (k <= 4) : (k += 1) {
            glow(p_x - dash_dx * @as(f32, @floatFromInt(k)) * 7, p_y - dash_dy * @as(f32, @floatFromInt(k)) * 7, p_r * (1.0 - @as(f32, @floatFromInt(k)) * 0.18), C_PLAYER, 0.35);
        }
    }
    const blink = invul > 0 and @mod(@as(i32, @intFromFloat(invul * 20)), 2) == 0;
    if (!blink) {
        glow(p_x, p_y, p_r * 2.2, C_PLAYER, 0.4);
        orb(p_x, p_y, p_r, if (hurt_t > 0.2) 0xff6677 else C_PLAYER, 1.0);
        orb(p_x, p_y, p_r * 0.45, 0xffffff, 0.85);
        ring(p_x, p_y, p_r + 2.5, 1.0, C_PLAYER, 0.7);
    }
    // aim indicator
    orb(p_x + p_aimx * (p_r + 6), p_y + p_aimy * (p_r + 6), 2.0, 0xffffff, 0.9);
    if (muzzle > 0) {
        glow(p_x + p_aimx * (p_r + 4), p_y + p_aimy * (p_r + 4), 9, 0xfff0c0, 1.2);
    }
    // thorns aura
    if (s_thorns > 0) ring(p_x, p_y, p_r + 34, 0.8, 0x8dffb0, 0.18);
}

fn renderBullet(b: *Bullet) void {
    if (b.enemy) {
        glow(b.x, b.y, b.rad * 2.4, b.col, 0.45);
        orb(b.x, b.y, b.rad, b.col, 1.0);
        orb(b.x, b.y, b.rad * 0.4, 0xffffff, 0.7);
    } else {
        glow(b.x, b.y, b.rad * 2.6, b.col, 0.5);
        orb(b.x, b.y, b.rad, b.col, 1.0);
        orb(b.x, b.y, b.rad * 0.45, 0xffffff, 0.9);
    }
}

fn render() void {
    clearBuf(5, 6, 11);
    drawGrid();
    // arena border
    rectAdd(9, 9, 462, 1, 0x1d2a44, 1.0);
    rectAdd(9, 260, 462, 1, 0x1d2a44, 1.0);
    rectAdd(9, 9, 1, 252, 0x1d2a44, 1.0);
    rectAdd(470, 9, 1, 252, 0x1d2a44, 1.0);

    for (&crystals) |*c| {
        if (c.on) {
            const pulse = 1.0 + @sin(g_time * 8 + c.x) * 0.2;
            glow(c.x, c.y, 6 * pulse, C_XP, 0.5);
            orb(c.x, c.y, 2.4 * pulse, C_XP, 1.0);
        }
    }
    for (&parts) |*p| {
        if (p.on) {
            const a = clampf(p.life / p.maxlife, 0, 1);
            glow(p.x, p.y, p.rad * 1.6, p.col, a * 0.9);
            orb(p.x, p.y, p.rad * a, p.col, a);
        }
    }
    for (&enemies) |*e| { if (e.on) renderEnemy(e); }
    for (&bullets) |*b| { if (b.on) renderBullet(b); }
    renderPlayer();

    if (flash_white > 0) {
        const g: f32 = flash_white;
        var i: usize = 0;
        while (i < FBSZ) : (i += 4) {
            fb[i] = addSat(fb[i], @intFromFloat(clampf(220.0 * g, 0, 255)));
            fb[i + 1] = addSat(fb[i + 1], @intFromFloat(clampf(200.0 * g, 0, 255)));
            fb[i + 2] = addSat(fb[i + 2], @intFromFloat(clampf(240.0 * g, 0, 255)));
        }
    }
}

fn cardRect(k: usize) [4]i32 {
    const xs = [_]i32{ 16, 169, 322 };
    return .{ xs[k], 66, 142, 150 };
}

fn renderHud() void {
    // HP
    drawBar(16, 16, 120, 7, p_hp / p_maxhp, 0x4dffa0);
    drawText(16, 26, "HP", 1, 0x8fffc0, 0.9);
    // XP
    drawBar(16, 34, 120, 4, g_xp / g_xpnext, C_XP);
    // heat
    const hcol: u32 = if (overheat > 0) 0xff5566 else if (heat > 0.7) 0xffb84d else 0x66c8ff;
    drawBar(146, 20, 40, 4, heat, hcol);

    var buf: [32]u8 = undefined;

    // score top-right
    const sc = @as(i64, @intFromFloat(g_score));
    const ss = fmtInt(&buf, sc);
    drawText(464 - textWidth(ss, 1), 14, ss, 1, 0xfff4e0, 1.0);

    // time + wave center
    const tsec = @as(i64, @intFromFloat(g_time));
    const mm = @divTrunc(tsec, 60);
    const sss = @mod(tsec, 60);
    var tb: [16]u8 = undefined;
    const ts = fmtTime(&tb, mm, sss);
    drawTextCentered(240, 14, ts, 1, 0xcfe6ff, 0.9);

    var wb: [16]u8 = undefined;
    const ws = fmtWave(&wb, wave);
    drawTextCentered(240, 24, ws, 1, 0xffc14d, 0.9);

    // level
    var lb: [16]u8 = undefined;
    const ls = fmtLvl(&lb, g_level);
    drawText(464 - textWidth(ls, 1), 24, ls, 1, 0x8fd9ff, 0.9);

    // combo
    if (combo >= 3) {
        var cbuf: [16]u8 = undefined;
        const cs = fmtCombo(&cbuf, combo);
        const cgain: f32 = clampf(combo_t / 2.2, 0.2, 1.0);
        drawTextCentered(240, 40, cs, 2, 0xffe08a, cgain);
    }

    // boss hp bar at bottom
    if (boss_alive) {
        for (&enemies) |*e| {
            if (e.on and e.kind == 5) {
                drawBar(90, 252, 300, 8, e.hp / e.maxhp, 0xff33cc);
                drawTextCentered(240, 240, "OVERSEER", 1, 0xff9de0, 1.0);
            }
        }
    }
}

fn renderCards() void {
    // dim
    var i: usize = 0;
    while (i < FBSZ) : (i += 4) {
        fb[i] = @intCast(@as(u16, fb[i]) * 45 / 100);
        fb[i + 1] = @intCast(@as(u16, fb[i + 1]) * 45 / 100);
        fb[i + 2] = @intCast(@as(u16, fb[i + 2]) * 45 / 100);
    }
    drawTextCentered(240, 26, "LEVEL UP - CHOOSE ONE", 2, 0xfff4e0, 1.0);
    for (0..3) |k| {
        const r = cardRect(k);
        const u = upgrades[card_choices[k]];
        // border
        rectAdd(r[0], r[1], r[2], 2, u.col, 1.0);
        rectAdd(r[0], r[1] + r[3] - 2, r[2], 2, u.col, 1.0);
        rectAdd(r[0], r[1], 2, r[3], u.col, 1.0);
        rectAdd(r[0] + r[2] - 2, r[1], 2, r[3], u.col, 1.0);
        // fill
        rectAdd(r[0] + 3, r[1] + 3, r[2] - 6, r[3] - 6, u.col, 0.06);
        // number
        var nb: [4]u8 = undefined;
        nb[0] = @intCast('1' + @as(u8, @intCast(k)));
        drawText(r[0] + @divTrunc(r[2], 2) - 3, r[1] + 10, nb[0..1], 2, u.col, 1.0);
        // name (wrap by words at ~19 chars scale1)
        drawTextCentered(r[0] + @divTrunc(r[2], 2), r[1] + 34, u.name, 1, 0xffffff, 1.0);
        drawTextCentered(r[0] + @divTrunc(r[2], 2), r[1] + 52, u.desc, 1, u.col, 0.95);
        // hint
        drawTextCentered(r[0] + @divTrunc(r[2], 2), r[1] + r[3] - 16, "SELECT", 1, 0x9aa4b2, 0.8);
    }
}

fn renderTitle() void {
    const t = g_time;
    // floating orbs bg
    var k: i32 = 0;
    while (k < 14) : (k += 1) {
        const fx = @mod(@as(f32, @floatFromInt(k)) * 137.5 + t * (8 + @as(f32, @floatFromInt(@mod(k, 5))) * 4), 480);
        const fy = 40 + @sin(t * 0.7 + @as(f32, @floatFromInt(k))) * 60 + @as(f32, @floatFromInt(@mod(k, 6))) * 30;
        glow(fx, fy, 5, TITLE_PAL[@intCast(@mod(k, 4))], 0.5);
    }
    const bob = @sin(t * 2.0) * 3;
    drawTextCentered(240, @intFromFloat(70 + bob), "RAD DRIFT", 5, 0x66f0ff, 1.0);
    drawTextCentered(240, 118, "A NEON ARENA ROGUELITE", 1, 0xffc14d, 0.95);
    drawTextCentered(240, 150, "WASD MOVE   AUTO-FIRE  SPACE DASH", 1, 0xcfe6ff, 0.9);
    drawTextCentered(240, 162, "DASH THROUGH FOES TO DAMAGE THEM", 1, 0x9d7dff, 0.9);
    drawTextCentered(240, 174, "COLLECT SHARDS  LEVEL UP  CHOOSE PERKS", 1, 0x9d7dff, 0.9);
    drawTextCentered(240, 186, "DONT OVERHEAT YOUR WEAPON", 1, 0xff9a6a, 0.9);
    const pulse = 0.55 + 0.45 * @sin(t * 4.0);
    drawTextCentered(240, 214, "PRESS SPACE OR CLICK TO START", 2, 0xffffff, pulse);
    drawTextCentered(240, 246, "NO LIBC - ZIG -> WASM", 1, 0x4c5a70, 0.8);
}

fn renderDead() void {
    drawTextCentered(240, 50, "YOU DIED", 5, 0xff4d6d, 1.0);
    var buf: [32]u8 = undefined;
    const sc = @as(i64, @intFromFloat(g_score));
    const ss = fmtInt(&buf, sc);
    drawTextCentered(240, 116, "SCORE", 1, 0x9aa4b2, 0.9);
    drawTextCentered(240, 128, ss, 3, 0xfff4e0, 1.0);
    var buf2: [32]u8 = undefined;
    const ts = fmtStat(&buf2, g_time);
    drawTextCentered(240, 164, ts, 1, 0xcfe6ff, 0.9);
    var buf3: [32]u8 = undefined;
    const ks = fmtKills(&buf3, kills, wave, g_level);
    drawTextCentered(240, 178, ks, 1, 0xcfe6ff, 0.9);
    const pulse = 0.55 + 0.45 * @sin(g_time * 4.0);
    drawTextCentered(240, 214, "PRESS R OR CLICK TO RETRY", 2, 0xffffff, pulse);
}

// ---- small number formatters (no libc) ----
fn fmtInt(buf: []u8, v: i64) []const u8 {
    var tmp: [24]u8 = undefined;
    var n: usize = 0;
    const neg = v < 0;
    var u: u64 = if (v < 0) @intCast(-v) else @intCast(v);
    if (u == 0) { tmp[0] = '0'; n = 1; }
    while (u > 0) : (u /= 10) { tmp[n] = @intCast('0' + (u % 10)); n += 1; }
    var i: usize = 0;
    if (neg) { buf[i] = '-'; i += 1; }
    var j = n;
    while (j > 0) : (j -= 1) { buf[i] = tmp[j - 1]; i += 1; }
    return buf[0..i];
}
fn pad2(buf: []u8, off: usize, v: i64) usize {
    buf[off] = @intCast('0' + @as(u8, @intCast(@mod(@divTrunc(v, 10), 10))));
    buf[off + 1] = @intCast('0' + @as(u8, @intCast(@mod(v, 10))));
    return off + 2;
}
fn fmtTime(buf: []u8, mm: i64, ss: i64) []const u8 {
    var o: usize = 0;
    o = pad2(buf, o, mm);
    buf[o] = ':'; o += 1;
    o = pad2(buf, o, ss);
    return buf[0..o];
}
fn fmtWave(buf: []u8, w: i32) []const u8 {
    buf[0] = 'W'; buf[1] = 'A'; buf[2] = 'V'; buf[3] = 'E'; buf[4] = ' '; buf[5] = @intCast('0' + @as(u8, @intCast(@mod(w, 10))));
    return buf[0..6];
}
fn fmtLvl(buf: []u8, l: i32) []const u8 {
    buf[0] = 'L'; buf[1] = 'V'; buf[2] = ' '; buf[3] = @intCast('0' + @as(u8, @intCast(@mod(l, 10))));
    return buf[0..4];
}
fn fmtCombo(buf: []u8, c: i32) []const u8 {
    buf[0] = 'x'; buf[1] = @intCast('0' + @as(u8, @intCast(@mod(@divTrunc(c, 10), 10)))); buf[2] = @intCast('0' + @as(u8, @intCast(@mod(c, 10))));
    return if (c >= 10) buf[0..3] else buf[1..3];
}
fn fmtStat(buf: []u8, t: f32) []const u8 {
    const tt = @as(i64, @intFromFloat(t));
    var o: usize = 0;
    const pre = "SURVIVED ";
    for (pre) |ch| { buf[o] = ch; o += 1; }
    const s = fmtInt(buf[o .. o + 12], tt);
    o += s.len;
    buf[o] = 'S'; o += 1;
    return buf[0..o];
}
fn fmtKills(buf: []u8, k: i32, w: i32, l: i32) []const u8 {
    var o: usize = 0;
    const pre = "KILLS ";
    for (pre) |ch| { buf[o] = ch; o += 1; }
    const s = fmtInt(buf[o .. o + 12], k);
    o += s.len;
    buf[o] = ' '; o += 1;
    buf[o] = 'W'; o += 1; buf[o] = @intCast('0' + @as(u8, @intCast(@mod(w, 10)))); o += 1;
    buf[o] = ' '; o += 1;
    buf[o] = 'L'; o += 1; buf[o] = @intCast('0' + @as(u8, @intCast(@mod(l, 10)))); o += 1;
    return buf[0..o];
}

// ============================================================================
//  EXPORTS
// ============================================================================
fn resetGame() void {
    for (&bullets) |*b| { b.on = false; }
    for (&enemies) |*e| { e.on = false; }
    for (&parts) |*p| { p.on = false; }
    for (&crystals) |*c| { c.on = false; }
    p_x = 240; p_y = 135; p_vx = 0; p_vy = 0;
    p_hp = 100; p_maxhp = 100; p_r = 7;
    s_dmg = 9; s_fire = 0.30; s_bspeed = 320; s_bsize = 2.6; s_multi = 1; s_spread = 0.18;
    s_pierce = 0; s_crit = 0.05; s_critm = 2.2; s_homing = 0; s_knock = 160; s_lifesteal = 0;
    s_expl = 0; s_speed = 108; s_dashcd = 1.3; s_dashdmg = 22; s_regen = 0; s_magnet = 58;
    s_xpm = 1; s_thorns = 0; s_armor = 0;
    dash_t = 0; dash_cd = 0; dash_idx = 0; invul = 0.5; fire_t = 0; muzzle = 0; heat = 0; overheat = 0;
    hurt_t = 0; regen_acc = 0;
    g_time = 0; g_score = 0; g_xp = 0; g_level = 1; g_xpnext = 6;
    combo = 0; combo_t = 0; kills = 0; wave = 1; wave_t = 0; spawn_t = 0.8; calm_t = 0;
    shake = 0; hitstop = 0; banner = 1.6; banner_txt = "WAVE 1"; boss_alive = false; flash_white = 0;
    cards_active = false;
    ev_shoot = 0; ev_hit = 0; ev_kill = 0; ev_hurt = 0; ev_boom = 0; ev_level = 0;
    state = 1;
}

export fn init(seed: u32) void {
    rndSeed(seed);
    state = 0;
    g_time = 0;
}

export fn frame(dt_ms: f32) void {
    var dt = dt_ms * 0.001;
    if (dt > 0.05) dt = 0.05;
    if (dt < 0) dt = 0;

    // shake offsets
    if (shake > 0.1) {
        shx = (rnd() * 2 - 1) * shake;
        shy = (rnd() * 2 - 1) * shake;
    } else { shx = 0; shy = 0; }

    const real_dt = dt;
    var edt = dt;
    if (hitstop > 0) { edt = dt * 0.16; hitstop = @max(0, hitstop - real_dt); }

    switch (state) {
        0 => { g_time += real_dt; },
        1 => { updateGame(edt); },
        2 => { g_time += real_dt * 0.2; },
        3 => { g_time += real_dt; updateParticles(real_dt); if (shake > 0) shake = @max(0, shake - real_dt * 26); },
        else => {},
    }

    render();
    switch (state) {
        0 => renderTitle(),
        1 => if (state == 1) renderHud(),
        2 => { renderHud(); renderCards(); },
        3 => { renderHud(); renderDead(); },
        else => {},
    }
    if (state == 1 and banner > 0) {
        var bb: [24]u8 = undefined;
        var o: usize = 0;
        for (banner_txt) |ch| { if (o < bb.len) { bb[o] = ch; o += 1; } }
        const g: f32 = clampf(banner, 0, 1);
        drawTextCentered(240, 92, bb[0..o], 2, 0xfff4e0, g);
    }
}

fn keyBit(code: u32) u32 {
    return switch (code) {
        KW, 38 => 1, // W / UP
        KA, 37 => 2, // A / LEFT
        KS, 40 => 4, // S / DOWN
        KD, 39 => 8, // D / RIGHT
        KSPACE => 16,
        else => 0,
    };
}

export fn key(code: u32, down: u32) void {
    const bit = keyBit(code);
    if (down == 1) {
        if (bit != 0) keys |= bit;
        if (code == KSPACE or code == KENTER) {
            if (state == 0 or state == 3) { resetGame(); return; }
        }
        if (code == KR and state == 3) { resetGame(); return; }
        if (state == 2) {
            if (code == K1) {
                applyCard(0);
            } else if (code == K2) {
                applyCard(1);
            } else if (code == K3) {
                applyCard(2);
            }
        }
    } else {
        if (bit != 0) keys &= ~bit;
    }
}

export fn mousemove(x: f32, y: f32) void {
    mouse_x = clampf(x, 0, @floatFromInt(W));
    mouse_y = clampf(y, 0, @floatFromInt(H));
}

export fn mousedown(down: u32) void {
    if (down == 1) {
        if (state == 0 or state == 3) { resetGame(); return; }
        if (state == 2) {
            for (0..3) |k| {
                const r = cardRect(k);
                if (mouse_x >= @as(f32, @floatFromInt(r[0])) and mouse_x <= @as(f32, @floatFromInt(r[0] + r[2])) and
                    mouse_y >= @as(f32, @floatFromInt(r[1])) and mouse_y <= @as(f32, @floatFromInt(r[1] + r[3]))) {
                    applyCard(k);
                    return;
                }
            }
        }
    }
}

export fn fbptr() [*]u8 { return &fb; }
export fn fw() i32 { return W; }
export fn fh() i32 { return H; }

// --- debug / test hooks ---
export fn dbg_state() i32 { return state; }
export fn dbg_setstate(s: i32) void { state = @intCast(@mod(s, 4) & 3); }
export fn dbg_play() void { resetGame(); }
export fn dbg_score() f32 { return g_score; }
export fn dbg_time() f32 { return g_time; }
export fn dbg_hp() f32 { return p_hp; }
export fn dbg_kills() i32 { return kills; }
export fn dbg_count_enemies() i32 {
    var n: i32 = 0;
    for (&enemies) |*e| { if (e.on) n += 1; }
    return n;
}
export fn dbg_count_bullets() i32 {
    var n: i32 = 0;
    for (&bullets) |*b| { if (b.on) n += 1; }
    return n;
}
export fn dbg_spawn(kind: u32, x: f32, y: f32) void { spawnEnemyAt(@intCast(kind), x, y, 1.0); }
export fn dbg_give_xp(v: f32) void { g_xp += v; }

export fn dbg_px() f32 { return p_x; }
export fn dbg_py() f32 { return p_y; }
export fn dbg_ex(i: i32) f32 { return enemies[@intCast(i)].x; }
export fn dbg_ey(i: i32) f32 { return enemies[@intCast(i)].y; }
export fn dbg_ekind(i: i32) i32 { return @intCast(enemies[@intCast(i)].kind); }
export fn dbg_ehp(i: i32) f32 { return enemies[@intCast(i)].hp; }
export fn dbg_ncrystals() i32 { var n: i32 = 0; for (crystals) |c| { if (c.on) n += 1; } return n; }
export fn dbg_nbullets() i32 { var n: i32 = 0; for (bullets) |b| { if (b.on) n += 1; } return n; }
export fn dbg_bx(i: i32) f32 { return bullets[@intCast(i)].x; }
export fn dbg_by(i: i32) f32 { return bullets[@intCast(i)].y; }
export fn dbg_bvx(i: i32) f32 { return bullets[@intCast(i)].vx; }
export fn dbg_bvy(i: i32) f32 { return bullets[@intCast(i)].vy; }
export fn dbg_benemy(i: i32) i32 { return if (bullets[@intCast(i)].enemy) 1 else 0; }
export fn dbg_cx(i: i32) f32 { return crystals[@intCast(i)].x; }
export fn dbg_cy(i: i32) f32 { return crystals[@intCast(i)].y; }
export fn dbg_best() f32 { return g_score; }
export fn dbg_wave_n() i32 { return wave; }

export fn ev(i: i32) i32 {
    return switch (i) {
        0 => ev_shoot, 1 => ev_hit, 2 => ev_kill, 3 => ev_hurt, 4 => ev_boom, 5 => ev_level,
        else => 0,
    };
}
