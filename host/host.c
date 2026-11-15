// SR2 Tweak Menu host - runs the SR Tweak Menu's Lua inside Saints Row 2 (PC).
//
// Built as dinput8.dll: Saints Row 2 imports one function from it
// (DirectInput8Create), so Windows loads this file from the game folder and
// we pass that call on to the real dinput8.dll in System32. On the way the
// keyboard device is wrapped, so the menu can keep keys from the game while
// it is open (wml.take_key).
//
// Lua 5.4 runs on the game's main thread, from the per-frame call at
// 0x0052050C. The menu's text is drawn with the game's own text printer from
// the 2D call at 0x00521A69. Juiced Patch hooks both calls itself; we wait
// until it has, then point the calls at our thunks and pass on to whatever
// they called before (Juiced's hooks, or the game's own functions without
// Juiced). The thunks keep every register and flag, so neither side notices.
//
// The Lua side sees a `wml` table shaped like Whompay's Mod Loader's (the
// SR1 menu's host), so the menu's own files run unchanged:
//   log, setting, mod_folder, mod_name, read_u8/u16/u32/f32, write_..., key_down,
//   key_pressed, take_key, force_key, on_frame, hook (not available, errors)
// and for SR2: script(code) runs Lua on the game's own state, call(addr, ...)
// calls a cdecl game function with up to 8 integer arguments, pad() reads
// controller 1 (buttons, lt, rt), f2u/u2f convert floats to bits and back.
//
// The menu's text "mailbox" (menu.lua writes the finished text to guest
// address 0x00F00000 for SR1's menu_overlay.dll) is emulated here: reads and
// writes in that range go to our own buffer, big-endian like the SR1 guest,
// and the text is drawn from it.

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <ctype.h>
#include <share.h>
#include <stdint.h>
#include <string.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

// ------------------------------------------------------------------ SR2 facts
// (addresses of the Steam/GOG build, the one Juiced Patch supports)
#define FRAME_CALL_SITE   0x0052050C   // per-frame call in the main loop (game: 0x00C063D0)
#define FRAME_CALL_GAME   0x00C063D0
#define DRAW_CALL_SITE    0x00521A69   // 2D text colour reset, after the frame's 2D (game: 0x00D14770)
#define DRAW_CALL_GAME    0x00D14770
#define LUA_STATE_PTR     0x0252983C   // the game's Lua state (lua_State**)
#define LUA_DOSTRING      0x00CDA000   // esi = state, eax = code
#define TEXT_PRINT        0x00D15DC0   // esi = text, edi = font, [esp] = x, [esp+4] = y (1280x720 space)
#define TEXT_COLOUR       0x00D14840   // cdecl (r, g, b, a)
#define FONT_SMALL_PTR    0x00E98A24
#define FONT_MEDIUM_PTR   0x00E98A90
#define VINT_RES_X        0x022F63F8   // screen size the 2D layer is laid out for
#define VINT_RES_Y        0x022F63FC

// ------------------------------------------------------------------ state
static char g_game_dir[MAX_PATH], g_root[MAX_PATH], g_mod_folder[MAX_PATH], g_ini[MAX_PATH], g_log_path[MAX_PATH];
static FILE *g_log;
static lua_State *L;
static int g_lua_failed, g_frame_count;
static uint32_t g_frame_prev = FRAME_CALL_GAME, g_draw_prev = DRAW_CALL_GAME;
static CRITICAL_SECTION g_lock;

// The SR1 menu's mailbox: magic, sequence at +0x10, length at +0x14, text at +0x40.
#define MAILBOX       0x00F00000u
#define MAILBOX_MAGIC 0x53524D55u
#define MAILBOX_SIZE  (0x40 + 8192)
static uint8_t g_mailbox[MAILBOX_SIZE];

// Keys: Windows virtual-key state this frame and last frame; DirectInput
// scancodes the menu has taken from the game.
static uint8_t g_key_now[256], g_key_prev[256];
static volatile uint8_t g_taken[256];

// Overlay layout (mod.ini: overlay_x, overlay_y, overlay_line, overlay_font).
static int g_ov_x = 60, g_ov_y = 70, g_ov_line = 20, g_ov_font = 6;

// ------------------------------------------------------------------ log
static void logf(const char *fmt, ...)
{
    if (!g_log) return;
    SYSTEMTIME t; GetLocalTime(&t);
    fprintf(g_log, "[%02d:%02d:%02d] ", t.wHour, t.wMinute, t.wSecond);
    va_list ap; va_start(ap, fmt); vfprintf(g_log, fmt, ap); va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
}

// ------------------------------------------------------------------ memory
static int in_mailbox(uint32_t a, uint32_t n) { return a >= MAILBOX && a + n <= MAILBOX + MAILBOX_SIZE; }

// Reads and writes outside the mailbox go to the game's memory; a bad
// address becomes a Lua error instead of a crash.
static int mem_read(uint32_t a, void *out, uint32_t n)
{
    __try { memcpy(out, (void *)(uintptr_t)a, n); return 1; }
    __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}
static int mem_write(uint32_t a, const void *in, uint32_t n)
{
    __try { memcpy((void *)(uintptr_t)a, in, n); return 1; }
    __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}

static uint32_t mailbox_get(uint32_t a, int n)
{
    if (a == MAILBOX && n == 4) return MAILBOX_MAGIC;   // "the overlay is here"
    uint32_t v = 0;
    for (int i = 0; i < n; i++) v = (v << 8) | g_mailbox[a - MAILBOX + i];
    return v;
}
static void mailbox_set(uint32_t a, int n, uint32_t v)
{
    EnterCriticalSection(&g_lock);
    for (int i = n - 1; i >= 0; i--) { g_mailbox[a - MAILBOX + i] = (uint8_t)v; v >>= 8; }
    LeaveCriticalSection(&g_lock);
}

static uint32_t check_addr(lua_State *s, int i) { return (uint32_t)luaL_checkinteger(s, i); }

static int l_read(lua_State *s, int n)
{
    uint32_t a = check_addr(s, 1), v = 0;
    if (in_mailbox(a, n)) { lua_pushinteger(s, mailbox_get(a, n)); return 1; }
    if (!mem_read(a, &v, n)) return luaL_error(s, "bad read at %p", (void *)(uintptr_t)(a));
    lua_pushinteger(s, v);
    return 1;
}
static int l_read_u8(lua_State *s)  { return l_read(s, 1); }
static int l_read_u16(lua_State *s) { return l_read(s, 2); }
static int l_read_u32(lua_State *s) { return l_read(s, 4); }
static int l_read_f32(lua_State *s)
{
    uint32_t a = check_addr(s, 1); float f;
    if (!mem_read(a, &f, 4)) return luaL_error(s, "bad read at %p", (void *)(uintptr_t)(a));
    lua_pushnumber(s, f);
    return 1;
}
static int l_write(lua_State *s, int n)
{
    uint32_t a = check_addr(s, 1), v = (uint32_t)luaL_checkinteger(s, 2);
    if (in_mailbox(a, n)) { mailbox_set(a, n, v); return 0; }
    if (!mem_write(a, &v, n)) return luaL_error(s, "bad write at %p", (void *)(uintptr_t)(a));
    return 0;
}
static int l_write_u8(lua_State *s)  { return l_write(s, 1); }
static int l_write_u16(lua_State *s) { return l_write(s, 2); }
static int l_write_u32(lua_State *s) { return l_write(s, 4); }
static int l_write_f32(lua_State *s)
{
    uint32_t a = check_addr(s, 1); float f = (float)luaL_checknumber(s, 2);
    if (!mem_write(a, &f, 4)) return luaL_error(s, "bad write at %p", (void *)(uintptr_t)(a));
    return 0;
}
static int l_f2u(lua_State *s) { float f = (float)luaL_checknumber(s, 1); uint32_t u; memcpy(&u, &f, 4); lua_pushinteger(s, u); return 1; }
static int l_u2f(lua_State *s) { uint32_t u = (uint32_t)luaL_checkinteger(s, 1); float f; memcpy(&f, &u, 4); lua_pushnumber(s, f); return 1; }

// ------------------------------------------------------------------ the game's Lua
// The game has two Lua 5.0 states: the mission scripts' (gameplay functions
// such as cash_add, teleport) and the interface's ("vint": the HUD, menus,
// the phone and its cheats).
//
// Results come back through tweak_out(...), a C function we put in both
// states' globals: whatever a script passes it while wml.script/wml.vint
// runs is returned to our Lua. The game's Lua is stock 5.0: a TObject is 16
// bytes (type, then the value at +8, numbers are doubles), L->top is at +8,
// L->base at +12, the globals table at +0x40, a string's text 16 bytes into it.
#define VINT_STATE_PTR    0x0252A1B8
#define LUA50_PUSHSTRING  0x00CDCAF0   // esi = state, [esp] = text
#define LUA50_PUSHCLOSURE 0x00CDCD30   // esi = state, [esp] = function, [esp+4] = upvalues
#define LUA50_RAWSET      0x00CD5380   // luaH_set: cdecl (state, Table *, key) -> the value's slot

#define OUT_MAX 128
typedef struct { int type; double n; char s[256]; } outval_t;
static outval_t g_out[OUT_MAX];
static int g_out_n;

static int __cdecl tweak_out(void *state)
{
    uint8_t *base = *(uint8_t **)((uint8_t *)state + 12), *top = *(uint8_t **)((uint8_t *)state + 8);
    static int told;
    if (!told++) logf("tweak_out called: %d values", (int)((top - base) / 16));
    for (uint8_t *o = base; o < top && g_out_n < OUT_MAX; o += 16) {
        outval_t *v = &g_out[g_out_n++];
        v->type = *(int *)o;
        v->s[0] = 0;
        if (v->type == 1) v->n = *(int *)(o + 8);                       // boolean
        else if (v->type == 3) v->n = *(double *)(o + 8);               // number
        else if (v->type == 4) strncpy_s(v->s, sizeof v->s, *(char **)(o + 8) + 16, _TRUNCATE);  // string
    }
    return 0;
}

static void register_out(void *state)
{
    static int told;
    if (told < 4) { told++; logf("adding tweak_out to Lua state %p (top %08X base %08X)", state, *(uint32_t *)((uint8_t *)state + 8), *(uint32_t *)((uint8_t *)state + 12)); }
    static const char *name = "tweak_out";
    void *fn = (void *)tweak_out;
    __try {
        __asm {
            pushad
            mov esi, state
            push name
            mov eax, LUA50_PUSHSTRING
            call eax
            add esp, 4
            push 0
            push fn
            mov eax, LUA50_PUSHCLOSURE
            call eax
            add esp, 8
            popad
        }
        // A raw set (luaH_set, then the value copied in): the game guards its
        // globals with a metatable, which takes a plain settable of a new name.
        uint8_t **top = (uint8_t **)((uint8_t *)state + 8);
        uint8_t *globals = (uint8_t *)state + 0x40;
        if (*(int *)globals == 5) {
            uint8_t *table = *(uint8_t **)(globals + 8);
            uint8_t *slot = ((uint8_t *(__cdecl *)(void *, void *, void *))LUA50_RAWSET)(state, table, *top - 0x20);
            memcpy(slot, *top - 0x10, 16);
            table[6] = 0;   // (its metamethod cache)
        }
        *top -= 0x20;
    } __except (EXCEPTION_EXECUTE_HANDLER) { logf("couldn't add tweak_out to the game's Lua"); }
}

// Every couple of seconds (and whenever a state is new): the game can
// rebuild its states, losing our function.
static void keep_registered(void)
{
    static void *last_game, *last_vint;
    static int countdown;
    void *g = *(void **)LUA_STATE_PTR, *v = *(void **)VINT_STATE_PTR;
    if (--countdown > 0 && g == last_game && v == last_vint) return;
    countdown = 120;
    if (g) register_out(g);
    if (v) register_out(v);
    last_game = g; last_vint = v;
}

static int g_last_status;
static DWORD g_exception;
static int game_dostring(void *state, const char *code)
{
    if (!state) return 0;
    int status = 0;
    __try {
        __asm {
            pushad
            mov esi, state
            mov eax, code
            mov edx, LUA_DOSTRING
            call edx
            mov status, eax
            popad
        }
    } __except (g_exception = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) {
        logf("exception %08X in the game's Lua running: %.200s", g_exception, code);
        return -1;
    }
    g_last_status = status & 0xFF;
    return 1;
}
// Returns: true if it finished successfully (false: missing state or Lua error), then every value the
// code passed to tweak_out.
static int run_in(lua_State *s, uint32_t state_ptr)
{
    const char *code = luaL_checkstring(s, 1);
    keep_registered();
    g_out_n = 0;
    g_last_status = 0;
    int r = game_dostring(*(void **)state_ptr, code);
    if (r < 0) return luaL_error(s, "the game crashed running: %s", code);
    if (g_last_status) logf("game Lua (%s) status %d running: %.200s", state_ptr == VINT_STATE_PTR ? "vint" : "game", g_last_status, code);
    if (g_last_status) g_out_n = 0;  // never publish partial results from a failed native chunk
    lua_pushboolean(s, r == 1 && g_last_status == 0);
    int n = g_out_n;
    luaL_checkstack(s, n, "too many results");
    for (int i = 0; i < n; i++) {
        outval_t *v = &g_out[i];
        if (v->type == 1) lua_pushboolean(s, v->n != 0);
        else if (v->type == 3) {
            if (v->n == (double)(lua_Integer)v->n) lua_pushinteger(s, (lua_Integer)v->n); else lua_pushnumber(s, v->n);
        }
        else if (v->type == 4) lua_pushstring(s, v->s);
        else lua_pushnil(s);
    }
    return 1 + n;
}
static int l_script(lua_State *s) { return run_in(s, LUA_STATE_PTR); }
static int l_vint(lua_State *s)   { return run_in(s, VINT_STATE_PTR); }

// ------------------------------------------------------------------ game functions
// Both calls keep the x87 state as it was: a game function that returns a
// float leaves it on the FPU stack, and eight of those would overflow it.
static uint8_t g_fpu[108];
static void fpu_save(void) { __asm { fnsave g_fpu } __asm { frstor g_fpu } }
static void fpu_restore(void) { __asm { frstor g_fpu } }

typedef uint32_t (__cdecl *cdecl8)(uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
static int call_guarded(uint32_t fn, const uint32_t *a, uint32_t *out)
{
    fpu_save();
    __try { *out = ((cdecl8)(uintptr_t)fn)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); fpu_restore(); return 1; }
    __except (EXCEPTION_EXECUTE_HANDLER) { fpu_restore(); return 0; }
}
// A cdecl call with up to 8 integer arguments (extra ones are harmless: the
// caller cleans the stack).
static int l_call(lua_State *s)
{
    uint32_t fn = check_addr(s, 1), a[8] = { 0 }, r;
    int n = lua_gettop(s) - 1;
    if (n > 8) return luaL_error(s, "call: at most 8 arguments");
    for (int i = 0; i < n; i++) a[i] = (uint32_t)luaL_checkinteger(s, i + 2);
    if (!call_guarded(fn, a, &r)) return luaL_error(s, "call %p crashed", (void *)(uintptr_t)(fn));
    lua_pushinteger(s, r);
    return 1;
}

// callx(addr, regs, ...): many of SR2's functions take arguments in
// registers. regs = { eax =, ebx =, ecx =, edx =, esi =, edi = } (any of
// them), then up to 8 stack arguments; the caller cleans the stack. Returns eax.
static uint32_t cx_fn, cx_esp, cx_ret, cx_eax, cx_ebx, cx_ecx, cx_edx, cx_esi, cx_edi, cx_n, cx_args[8];
static __declspec(naked) void callx_thunk(void)
{
    __asm {
        pushad
        mov cx_esp, esp
        mov ecx, cx_n
    next_arg:
        test ecx, ecx
        jz args_done
        dec ecx
        push dword ptr [cx_args + ecx * 4]
        jmp next_arg
    args_done:
        mov eax, cx_eax
        mov ebx, cx_ebx
        mov ecx, cx_ecx
        mov edx, cx_edx
        mov esi, cx_esi
        mov edi, cx_edi
        call dword ptr [cx_fn]
        mov cx_ret, eax
        mov esp, cx_esp
        popad
        ret
    }
}
static int callx_guarded(void)
{
    fpu_save();
    __try { callx_thunk(); fpu_restore(); return 1; }
    __except (EXCEPTION_EXECUTE_HANDLER) { fpu_restore(); return 0; }
}
static uint32_t reg_field(lua_State *s, const char *name)
{
    lua_getfield(s, 2, name);
    uint32_t v = (uint32_t)luaL_optinteger(s, -1, 0);
    lua_pop(s, 1);
    return v;
}
static int l_callx(lua_State *s)
{
    cx_fn = check_addr(s, 1);
    luaL_checktype(s, 2, LUA_TTABLE);
    cx_eax = reg_field(s, "eax"); cx_ebx = reg_field(s, "ebx"); cx_ecx = reg_field(s, "ecx");
    cx_edx = reg_field(s, "edx"); cx_esi = reg_field(s, "esi"); cx_edi = reg_field(s, "edi");
    int n = lua_gettop(s) - 2;
    if (n > 8) return luaL_error(s, "callx: at most 8 stack arguments");
    cx_n = (uint32_t)n;
    for (int i = 0; i < n; i++) cx_args[i] = (uint32_t)luaL_checkinteger(s, i + 3);
    if (!callx_guarded()) return luaL_error(s, "callx %p crashed", (void *)(uintptr_t)(cx_fn));
    lua_pushinteger(s, cx_ret);
    return 1;
}

// buffer(slot [, text]): the address of a 1 KB scratch buffer (slots 0-15)
// for passing strings, vectors and out-values to the game; with text, the
// text is written there (zero-terminated) first.
static char g_buffers[16][1024];
static int l_buffer(lua_State *s)
{
    lua_Integer slot = luaL_checkinteger(s, 1);
    if (slot < 0 || slot > 15) return luaL_error(s, "buffer: slot 0-15");
    if (!lua_isnoneornil(s, 2)) {
        size_t n; const char *t = luaL_checklstring(s, 2, &n);
        if (n > 1023) n = 1023;
        memcpy(g_buffers[slot], t, n); g_buffers[slot][n] = 0;
    }
    lua_pushinteger(s, (lua_Integer)(uintptr_t)g_buffers[slot]);
    return 1;
}
// patch(addr, bytes): writes into the game's code or read-only data (made
// writable for the write, then put back).
static int l_patch(lua_State *s)
{
    uint32_t a = check_addr(s, 1);
    size_t n; const char *b = luaL_checklstring(s, 2, &n);
    DWORD old;
    if (!VirtualProtect((void *)(uintptr_t)a, n, PAGE_EXECUTE_READWRITE, &old)) return luaL_error(s, "patch: can't unprotect %p", (void *)(uintptr_t)(a));
    int ok = mem_write(a, b, (uint32_t)n);
    VirtualProtect((void *)(uintptr_t)a, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), (void *)(uintptr_t)a, n);
    if (!ok) return luaL_error(s, "patch: bad write at %p", (void *)(uintptr_t)(a));
    return 0;
}
// read_string(addr [, max]): a zero-terminated string from the game.
static int l_read_string(lua_State *s)
{
    uint32_t a = check_addr(s, 1);
    lua_Integer max = luaL_optinteger(s, 2, 256);
    char buf[1024];
    if (max > 1023) max = 1023;
    int n = 0;
    for (; n < max; n++) { if (!mem_read(a + n, &buf[n], 1)) return luaL_error(s, "bad read at %p", (void *)(uintptr_t)(a + n)); if (!buf[n]) break; }
    buf[n] = 0;
    lua_pushstring(s, buf);
    return 1;
}

// ------------------------------------------------------------------ keys
typedef struct { const char *name; uint8_t vk, dik, dik2; } key_t;
static const key_t KEYS[] = {
    { "UP", VK_UP, 0xC8 }, { "DOWN", VK_DOWN, 0xD0 }, { "LEFT", VK_LEFT, 0xCB }, { "RIGHT", VK_RIGHT, 0xCD },
    { "ENTER", VK_RETURN, 0x1C, 0x9C }, { "RETURN", VK_RETURN, 0x1C, 0x9C }, { "BACKSPACE", VK_BACK, 0x0E },
    { "PAGEUP", VK_PRIOR, 0xC9 }, { "PAGEDOWN", VK_NEXT, 0xD1 }, { "HOME", VK_HOME, 0xC7 }, { "END", VK_END, 0xCF },
    { "INSERT", VK_INSERT, 0xD2 }, { "DELETE", VK_DELETE, 0xD3 }, { "ESCAPE", VK_ESCAPE, 0x01 }, { "ESC", VK_ESCAPE, 0x01 },
    { "SHIFT", VK_SHIFT, 0x2A, 0x36 }, { "CTRL", VK_CONTROL, 0x1D, 0x9D }, { "CONTROL", VK_CONTROL, 0x1D, 0x9D },
    { "ALT", VK_MENU, 0x38, 0xB8 }, { "SPACE", VK_SPACE, 0x39 }, { "TAB", VK_TAB, 0x0F },
};
// Key name ("F5", "A", "UP", or a number: a Windows virtual-key code) to
// virtual key and DirectInput scancodes.
static int key_lookup(lua_State *s, int i, uint8_t *vk, uint8_t *dik, uint8_t *dik2)
{
    *dik = *dik2 = 0;
    if (lua_type(s, i) == LUA_TNUMBER) {
        *vk = (uint8_t)lua_tointeger(s, i);
        *dik = (uint8_t)MapVirtualKeyA(*vk, MAPVK_VK_TO_VSC);
        return 1;
    }
    char name[32]; const char *in = luaL_checkstring(s, i);
    size_t n = 0;
    for (; in[n] && n < sizeof name - 1; n++) name[n] = (char)toupper((unsigned char)in[n]);
    name[n] = 0;
    for (int k = 0; k < (int)(sizeof KEYS / sizeof *KEYS); k++)
        if (!strcmp(name, KEYS[k].name)) { *vk = KEYS[k].vk; *dik = KEYS[k].dik; *dik2 = KEYS[k].dik2; return 1; }
    if (name[0] == 'F' && name[1] >= '1' && name[1] <= '9') {
        int f = atoi(name + 1);
        if (f >= 1 && f <= 24) { *vk = (uint8_t)(VK_F1 + f - 1); *dik = (uint8_t)MapVirtualKeyA(*vk, MAPVK_VK_TO_VSC); return 1; }
    }
    if (n == 1 && ((name[0] >= 'A' && name[0] <= 'Z') || (name[0] >= '0' && name[0] <= '9'))) {
        *vk = (uint8_t)name[0]; *dik = (uint8_t)MapVirtualKeyA(*vk, MAPVK_VK_TO_VSC); return 1;
    }
    return 0;
}

static int game_focused(void)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}
static void poll_keys(void)
{
    memcpy(g_key_prev, g_key_now, sizeof g_key_now);
    int focus = game_focused();
    for (int vk = 1; vk < 256; vk++) g_key_now[vk] = focus && (GetAsyncKeyState(vk) & 0x8000) ? 1 : 0;
}
static int l_key_down(lua_State *s)
{
    uint8_t vk, d1, d2;
    lua_pushboolean(s, key_lookup(s, 1, &vk, &d1, &d2) && g_key_now[vk]);
    return 1;
}
static int l_key_pressed(lua_State *s)
{
    uint8_t vk, d1, d2;
    lua_pushboolean(s, key_lookup(s, 1, &vk, &d1, &d2) && g_key_now[vk] && !g_key_prev[vk]);
    return 1;
}
// take_key(name, on): while on, the game doesn't see the key go down.
static int l_take_key(lua_State *s)
{
    uint8_t vk, d1, d2;
    if (!key_lookup(s, 1, &vk, &d1, &d2)) return luaL_error(s, "unknown key '%s'", lua_tostring(s, 1));
    int on = lua_toboolean(s, 2);
    if (d1) g_taken[d1] = (uint8_t)on;
    if (d2) g_taken[d2] = (uint8_t)on;
    return 0;
}
static int l_noop(lua_State *s) { (void)s; return 0; }

// Controller 1. The game reads its pads through XINPUT1_3's XInputGetState
// (imported by ordinal 2; with Juiced Patch that import leads to Juiced's
// SDL pads, so every kind of controller arrives as an Xbox one). The import
// is wrapped (hook_pad_import): what the game reads for pad 1 is kept for
// the menu, and while the menu has the controller the game gets nothing
// (or the buttons the menu hides) - SR1's menu does the same through its
// controller hook. Without that read (no wrap), XInput is asked directly.
typedef struct { DWORD packet; WORD buttons; BYTE lt, rt; SHORT lx, ly, rx, ry; } xstate_t;
typedef DWORD (WINAPI *xget_t)(DWORD, xstate_t *);
static xget_t g_xget, g_xget_game;
static xstate_t g_pad_seen;
static volatile DWORD g_pad_seen_at;
static volatile LONG g_pad_reads, g_polls;
static volatile LONG g_xinput_snapshot;
// Set by the menu each frame (wml.pad_filter): everything hidden, or these
// bits (PAD bits: buttons, 0x10000 LT, 0x20000 RT); and the open combo,
// whose last button is hidden while the ones held for it are down.
static volatile LONG g_pad_all;
static volatile LONG g_grab_remap, g_menu_capture;
static volatile DWORD g_pad_hide, g_combo_hold, g_combo_press;
// A press handed back to the game (wml.pad_inject): a short tap of a button
// the menu held back until it knew it was a tap.
static volatile DWORD g_pad_add;
static volatile LONG g_pad_add_reads;

static DWORD WINAPI my_xget(DWORD user, xstate_t *st)
{
    DWORD r = g_xget_game(user, st);
    if (user != 0 || r != 0 || !st) return r;
    g_pad_seen = *st;
    InterlockedExchange(&g_xinput_snapshot, 1);
    g_pad_seen_at = GetTickCount();
    InterlockedIncrement(&g_pad_reads);
    if (g_pad_all) {
        st->buttons = 0; st->lt = st->rt = 0; st->lx = st->ly = st->rx = st->ry = 0;
        return r;
    }
    DWORD hide = g_pad_hide;
    if (g_combo_hold && (st->buttons & g_combo_hold) == g_combo_hold) hide |= g_combo_press;
    st->buttons &= (WORD)~hide;
    if (hide & 0x10000) st->lt = 0;
    if (hide & 0x20000) st->rt = 0;
    if (g_pad_add_reads > 0) { st->buttons |= (WORD)g_pad_add; InterlockedDecrement(&g_pad_add_reads); }
    return r;
}
// The import slot of XINPUT1_3 ordinal 2 (XInputGetState) in SR2_pc.exe.
static void **xinput_import_slot(void)
{
    uint8_t *base = (uint8_t *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir.VirtualAddress) return NULL;
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
        if (_strnicmp((char *)(base + d->Name), "xinput", 6)) continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        IMAGE_THUNK_DATA *slots = (IMAGE_THUNK_DATA *)(base + d->FirstThunk);
        for (; names->u1.AddressOfData; names++, slots++) {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) {
                if (IMAGE_ORDINAL(names->u1.Ordinal) == 2) return (void **)&slots->u1.Function;
            } else if (!strcmp((char *)((IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData))->Name, "XInputGetState")) {
                return (void **)&slots->u1.Function;
            }
        }
    }
    return NULL;
}
static void hook_pad_import(void)
{
    void **slot = xinput_import_slot();
    if (!slot || !*slot) { logf("no XInputGetState import found; the menu can't keep the controller from the game"); return; }
    if (*slot == (void *)my_xget) return;
    DWORD old;
    if (!VirtualProtect(slot, sizeof *slot, PAGE_READWRITE, &old)) { logf("couldn't unprotect the XInputGetState import"); return; }
    g_xget_game = (xget_t)*slot;
    *slot = (void *)my_xget;
    VirtualProtect(slot, sizeof *slot, old, &old);
    logf("controller: XInputGetState import at %p wrapped (it went to %p)", (void *)slot, (void *)g_xget_game);
}

static int l_pad(lua_State *s)
{
    // What the game polled in the last half second, if its poll comes through a wrap.
    if ((g_polls > 0 || (g_xget_game && g_pad_reads > 0)) && GetTickCount() - g_pad_seen_at < 500) {
        if (!game_focused()) return 0;
        xstate_t st = g_pad_seen;
        lua_pushinteger(s, st.buttons); lua_pushinteger(s, st.lt); lua_pushinteger(s, st.rt);
        return 3;
    }
    static int tried;
    if (!tried) {
        tried = 1;
        HMODULE x = LoadLibraryA("xinput1_4.dll");
        if (!x) x = LoadLibraryA("xinput1_3.dll");
        if (x) g_xget = (xget_t)GetProcAddress(x, "XInputGetState");
    }
    xstate_t st;
    if (!g_xget || g_xget(0, &st) != 0 || !game_focused()) return 0;
    lua_pushinteger(s, st.buttons); lua_pushinteger(s, st.lt); lua_pushinteger(s, st.rt);
    return 3;
}
// The game's own poll of its pad device (one device, the global 0x023478A8):
// main pad poll 0x00C147D5 calls 0x00C13C80 (XInput) or, at 0x00C147DC,
// 0x00C141D0 (other pads); with Juiced Patch the pad arrives through
// Juiced (SDL) in the same device. After the poll the device holds one
// byte per button at [dev+0xF68] (0x80 down; [dev+0xF64] of them), mirrored
// to 0x02349808 (1 down): 0-3 A B X Y, 4-5 LB RB, 6-7 Back Start, 8-9 LS RS,
// 0xA-0xB LT RT (0-127), 0x10-0x13 D-pad right up left down; the sticks are
// floats at +0xD4C/+0xD50 and +0xD0C/+0xD10. Both calls are wrapped: the
// menu gets the pad as polled, then what it holds back is cleared before
// the game uses it.
#define PAD_DEV          0x023478A8
#define PAD_POLL_SITE_X  0x00C147D5
#define PAD_POLL_SITE_D  0x00C147DC
#define PAD_MIRROR       0x02349808
static uint32_t g_poll_prev_x, g_poll_prev_d;
static volatile LONG g_poll_hooks;      // polls seen through the call-site wraps
static volatile LONG g_polled_now;      // this update's poll came through them (its copy is the menu's)
static volatile LONG g_injected_now;    // buttons this poll put down for the game itself (wml.pad_inject)
static float g_sticks_poll[4];
static const struct { WORD bit; BYTE idx; } PADMAP[] = {
    { 0x1000, 0 }, { 0x2000, 1 }, { 0x4000, 2 }, { 0x8000, 3 }, { 0x0100, 4 }, { 0x0200, 5 },
    { 0x0020, 6 }, { 0x0010, 7 }, { 0x0040, 8 }, { 0x0080, 9 },
    { 0x0008, 0x10 }, { 0x0001, 0x11 }, { 0x0004, 0x12 }, { 0x0002, 0x13 },
};
static void remap_grab_buttons(uint8_t *buttons, uint8_t *mirror, WORD raw)
{
    if (!g_grab_remap || g_menu_capture || g_pad_all || (g_pad_hide & 0x8000)) return;
    buttons[3] = mirror[3] = 0;
    if (raw & 0x8000) { buttons[4] = 0x80; mirror[4] = 1; }
}
static void __cdecl after_pad_poll(uint8_t *dev)
{
    __try {
        uint8_t *b = *(uint8_t **)(dev + 0xF68);
        uint32_t n = *(uint32_t *)(dev + 0xF64);
        uint8_t *mirror = (uint8_t *)PAD_MIRROR;
        // (Juiced Patch's device counts 12 buttons; the D-pad is at 0x10-0x13 past them)
        if (!b || n < 12 || n > 64) return;
        uint32_t nb = n < 0x14 ? 0x14 : n;
        WORD buttons = 0;
        for (int i = 0; i < (int)(sizeof PADMAP / sizeof *PADMAP); i++) if (b[PADMAP[i].idx]) buttons |= PADMAP[i].bit;
        int raw_xinput = InterlockedExchange(&g_xinput_snapshot, 0);
        if (raw_xinput) buttons = g_pad_seen.buttons;
        // The menu's copy, as polled - before anything is held back, and before
        // the game turns the buttons into its actions (later in the update).
        g_pad_seen.buttons = buttons;
        if (!raw_xinput) {
            g_pad_seen.lt = (BYTE)(b[0xA] > 127 ? 255 : b[0xA] * 2);
            g_pad_seen.rt = (BYTE)(b[0xB] > 127 ? 255 : b[0xB] * 2);
        }
        g_pad_seen_at = GetTickCount();
        g_sticks_poll[0] = *(float *)(dev + 0xD0C); g_sticks_poll[1] = *(float *)(dev + 0xD10);
        g_sticks_poll[2] = *(float *)(dev + 0xD4C); g_sticks_poll[3] = *(float *)(dev + 0xD50);
        InterlockedIncrement(&g_poll_hooks);
        g_polled_now = 1;
        if (g_pad_all || (g_combo_hold && (buttons & g_combo_hold) == g_combo_hold && (buttons & g_combo_press))) {
            for (uint32_t i = 0; i < nb; i++) { b[i] = 0; mirror[i] = 0; }
            *(float *)(dev + 0xD4C) = 0; *(float *)(dev + 0xD50) = 0;
            *(float *)(dev + 0xD0C) = 0; *(float *)(dev + 0xD10) = 0;
        } else {
            DWORD hide = g_pad_hide;   // (the combo's last button is held back above, with everything)
            if (g_combo_hold && (buttons & g_combo_hold) == g_combo_hold) hide |= g_combo_press;
            for (int i = 0; i < (int)(sizeof PADMAP / sizeof *PADMAP); i++)
                if (hide & PADMAP[i].bit) { b[PADMAP[i].idx] = 0; mirror[PADMAP[i].idx] = 0; }
            if (hide & 0x10000) { b[0xA] = 0; mirror[0xA] = 0; }
            if (hide & 0x20000) { b[0xB] = 0; mirror[0xB] = 0; }
        }
        if (g_pad_add_reads > 0) {
            for (int i = 0; i < (int)(sizeof PADMAP / sizeof *PADMAP); i++)
                if (g_pad_add & PADMAP[i].bit) { b[PADMAP[i].idx] = 0x80; mirror[PADMAP[i].idx] = 1; }
            InterlockedExchange(&g_injected_now, (LONG)g_pad_add);
            InterlockedDecrement(&g_pad_add_reads);
        }
        remap_grab_buttons(b, mirror, buttons);
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
// After the game's whole input update (0x00C063D0, the per-frame call we
// hook): whoever polled the pad (the game, or Juiced Patch's SDL in place
// of 0x00C13C80), the device holds this frame's buttons. The menu's copy is
// taken, then - while the menu has the pad, or the open combo is down - the
// game's own "drop all input" (0x0075C700, eax = device: every one of its 87
// actions and 8 axes back to rest, what the game does itself when its input
// is blocked) runs, and the button bytes are cleared, so nothing reaches the
// game's controls this frame.
#define PAD_CLEAR_ALL 0x0075C700
static volatile LONG g_updates, g_update_blocks, g_update_leaks;
static float g_sticks[4];   // the device's stick floats as the game polled them (before any blocking)
static void pad_clear_all(void)
{
    __asm {
        pushad
        mov eax, PAD_DEV
        mov edx, PAD_CLEAR_ALL
        call edx
        popad
    }
}
static void __cdecl after_input_update(void)
{
    __try {
        uint8_t *dev = (uint8_t *)PAD_DEV;
        uint8_t *b = *(uint8_t **)(dev + 0xF68);
        uint32_t n = *(uint32_t *)(dev + 0xF64);
        uint8_t *mirror = (uint8_t *)PAD_MIRROR;
        InterlockedIncrement(&g_updates);
        // (Juiced Patch's device counts 12 buttons; the D-pad bytes are at
        // 0x10-0x13 past them either way)
        if (!b || n < 12 || n > 64) return;
        uint32_t nb = n < 0x14 ? 0x14 : n;
        WORD buttons = 0;
        int polled = g_polled_now;
        g_polled_now = 0;
        if (polled || g_poll_hooks > 0) {
            // The poll's copy. When an update comes without a poll, keep the
            // last poll's copy: rebuilding it from the bytes would read what
            // we held back as released, and the menu saw a held LB let go and
            // pressed again (the kick fired twice, the second time mid-kick).
            buttons = g_pad_seen.buttons;
        } else {
            for (int i = 0; i < (int)(sizeof PADMAP / sizeof *PADMAP); i++) if (b[PADMAP[i].idx]) buttons |= PADMAP[i].bit;
            g_pad_seen.buttons = buttons;
            g_pad_seen.lt = (BYTE)(b[0xA] > 127 ? 255 : b[0xA] * 2);
            g_pad_seen.rt = (BYTE)(b[0xB] > 127 ? 255 : b[0xB] * 2);
            g_pad_seen_at = GetTickCount();
        }
        InterlockedIncrement(&g_polls);
        int combo = g_combo_hold && (buttons & g_combo_hold) == g_combo_hold && (buttons & g_combo_press);
        if (polled) { for (int i = 0; i < 4; i++) g_sticks[i] = g_sticks_poll[i]; }
        else {
            g_sticks[0] = *(float *)(dev + 0xD0C); g_sticks[1] = *(float *)(dev + 0xD10);
            g_sticks[2] = *(float *)(dev + 0xD4C); g_sticks[3] = *(float *)(dev + 0xD50);
        }
        if (g_pad_all || combo) {
            for (uint32_t i = 0; i < nb; i++) { b[i] = 0; mirror[i] = 0; }
            *(float *)(dev + 0xD4C) = 0; *(float *)(dev + 0xD50) = 0;
            *(float *)(dev + 0xD0C) = 0; *(float *)(dev + 0xD10) = 0;
            pad_clear_all();
            InterlockedIncrement(&g_update_blocks);
        } else if (g_pad_hide) {
            // The hard lock. A held-back button is cleared at the poll, before
            // the game makes its actions from it - when the poll comes through
            // our wrap. When it doesn't (Juiced Patch's own poll, or a press
            // that landed between the poll and this update), the button is
            // still down here and the game has already turned it into an
            // action (a D-pad taunt while the menu scrolls, the grab under the
            // LB kick). Then every action is dropped for this update, as when
            // the menu has the whole pad: nothing held back ever gets through.
            // (Not a leak: what we put there ourselves - a tap handed back to
            // the game, and LB standing in for Y while the kick has LB.)
            DWORD ours = (DWORD)InterlockedExchange(&g_injected_now, 0);
            if (g_grab_remap && !g_menu_capture && !(g_pad_hide & 0x8000) && (buttons & 0x8000)) ours |= 0x0100;
            int leaked = 0;
            // The D-pad (taunt, compliment...) has no byte on Juiced Patch's
            // device (12 buttons, no 0x10-0x13): it reaches the game another
            // way, so no byte check sees it. Held back and down = drop every
            // action this update.
            if (buttons & g_pad_hide & 0x000F) leaked = 1;
            for (int i = 0; i < (int)(sizeof PADMAP / sizeof *PADMAP); i++)
                if (g_pad_hide & PADMAP[i].bit) {
                    if ((b[PADMAP[i].idx] || mirror[PADMAP[i].idx]) && !(ours & PADMAP[i].bit)) leaked = 1;
                    b[PADMAP[i].idx] = 0; mirror[PADMAP[i].idx] = 0;
                }
            if (g_pad_hide & 0x10000) { if (b[0xA] > 24) leaked = 1; b[0xA] = 0; mirror[0xA] = 0; }
            if (g_pad_hide & 0x20000) { if (b[0xB] > 24) leaked = 1; b[0xB] = 0; mirror[0xB] = 0; }
            if (leaked) {
                pad_clear_all();
                InterlockedIncrement(&g_update_leaks);
            }
        }
        if (!combo) remap_grab_buttons(b, mirror, buttons);
        // Evidence for the missing charged attack (both triggers held): after
        // a hold of about half a second, once per hold, what the pad gave and
        // what the game is left with after the menu's filter.
        {
            static int held, told;
            int both = g_pad_seen.lt > 128 && g_pad_seen.rt > 128;
            held = both ? held + 1 : 0;
            if (!both) told = 0;
            if (held == 30 && !told) {
                told = 1;
                logf("charge hold: pad LT %u RT %u; game sees LT %u RT %u (mirror %u %u); hide %08lX all %ld combo %d menu %ld remap %ld",
                    g_pad_seen.lt, g_pad_seen.rt, b[0xA], b[0xB], mirror[0xA], mirror[0xB],
                    (unsigned long)g_pad_hide, (long)g_pad_all, combo, (long)g_menu_capture, (long)g_grab_remap);
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
// sticks(): left x, y and right x, y, -1..1. From XInput when an Xbox pad
// answers (its layout is known), else the device's floats as polled.
static int l_sticks(lua_State *s)
{
    if (!g_xget) {
        static int tried;
        if (!tried) {
            tried = 1;
            HMODULE x = LoadLibraryA("xinput1_4.dll");
            if (!x) x = LoadLibraryA("xinput1_3.dll");
            if (x) g_xget = (xget_t)GetProcAddress(x, "XInputGetState");
        }
    }
    xstate_t st;
    if (g_xget && g_xget(0, &st) == 0 && game_focused()) {
        lua_pushnumber(s, st.lx / 32767.0); lua_pushnumber(s, st.ly / 32767.0);
        lua_pushnumber(s, st.rx / 32767.0); lua_pushnumber(s, st.ry / 32767.0);
        lua_pushstring(s, "xinput");
        return 5;
    }
    for (int i = 0; i < 4; i++) lua_pushnumber(s, g_sticks[i]);
    lua_pushstring(s, "device");
    return 5;
}
// pad_debug(): updates seen, of them with a pad device, of them blocked,
// the device's button count, polls through the wrap, and updates where a
// held-back button was still down afterwards (the hard lock dropped it).
static int l_pad_debug(lua_State *s)
{
    lua_pushinteger(s, g_updates); lua_pushinteger(s, g_polls); lua_pushinteger(s, g_update_blocks);
    lua_pushinteger(s, *(uint32_t *)(PAD_DEV + 0xF64));
    lua_pushinteger(s, g_poll_hooks);
    lua_pushinteger(s, g_update_leaks);   // held-back buttons found down after the update (all actions dropped)
    return 6;
}

static __declspec(naked) void pad_poll_thunk_x(void)
{
    __asm {
        push dword ptr [esp + 4]
        call dword ptr [g_poll_prev_x]
        add esp, 4
        pushad
        pushfd
        push dword ptr [esp + 40]
        call after_pad_poll
        add esp, 4
        popfd
        popad
        ret
    }
}
static __declspec(naked) void pad_poll_thunk_d(void)
{
    __asm {
        push dword ptr [esp + 4]
        call dword ptr [g_poll_prev_d]
        add esp, 4
        pushad
        pushfd
        push dword ptr [esp + 40]
        call after_pad_poll
        add esp, 4
        popfd
        popad
        ret
    }
}

// pad_filter(all, hide, combo_hold, combo_press): what the game doesn't see
// of controller 1 from now on (see my_xget).
static int l_pad_filter(lua_State *s)
{
    g_pad_all = g_menu_capture || lua_toboolean(s, 1);
    g_pad_hide = (DWORD)luaL_optinteger(s, 2, 0);
    g_combo_hold = (DWORD)luaL_optinteger(s, 3, 0);
    g_combo_press = (DWORD)luaL_optinteger(s, 4, 0);
    return 0;
}
static int l_menu_capture(lua_State *s)
{
    InterlockedExchange(&g_menu_capture, lua_toboolean(s, 1));
    if (g_menu_capture) { g_pad_hide |= 0x3FFFF; g_pad_all = 1; }
    if (!g_menu_capture) g_pad_all = 0;
    return 0;
}
static int l_grab_remap(lua_State *s)
{
    InterlockedExchange(&g_grab_remap, lua_toboolean(s, 1));
    return 0;
}
// pad_inject(bits, reads): the game sees these buttons down for its next
// `reads` reads of controller 1.
static int l_pad_inject(lua_State *s)
{
    g_pad_add = (DWORD)luaL_checkinteger(s, 1) & 0xFFFF;
    g_pad_add_reads = (LONG)luaL_optinteger(s, 2, 4);
    return 0;
}
// pad_source(): "game" when the game's own controller reads come through
// the wrap (so the menu can keep the controller from it), else "xinput".
static int l_pad_source(lua_State *s)
{
    lua_pushstring(s, (g_polls > 0 || (g_xget_game && g_pad_reads > 0)) ? "game" : "xinput");
    return 1;
}

// ------------------------------------------------------------------ field of view
// The game's camera field of view getter (0x00494080, three callers: the
// camera, the renderer's setup and cutscenes) is wrapped, whatever it is by
// then (the game's own, or Juiced Patch's FOVMultiplier / FixUltrawideFOV
// hook on it), and its result multiplied by the menu's factor
// (wml.set_fov). The menu's rows used to patch an instruction inside it,
// which Juiced also changes.
#define FOV_GETTER 0x00494080
static const uint8_t FOV_GETTER_BYTES[8] = { 0x51, 0x80, 0x3D, 0x14, 0x7D, 0x52, 0x02, 0x00 };
static float g_fov_mult = 1.0f;
static uint8_t *g_fov_tramp;
static int g_fov_hooked;
static __declspec(naked) void fov_thunk(void)
{
    __asm {
        call dword ptr [g_fov_tramp]
        fmul dword ptr [g_fov_mult]
        ret
    }
}
static void hook_fov(void)
{
    uint8_t *site = (uint8_t *)FOV_GETTER;
    g_fov_tramp = (uint8_t *)VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!g_fov_tramp) return;
    if (site[0] == 0xE9) {
        // Already a jump (another hook): ours goes first and calls on to it.
        uint32_t target = (uint32_t)(uintptr_t)site + 5 + *(int32_t *)(site + 1);
        g_fov_tramp[0] = 0xE9;
        *(int32_t *)(g_fov_tramp + 1) = (int32_t)(target - ((uint32_t)(uintptr_t)g_fov_tramp + 5));
    } else if (!memcmp(site, FOV_GETTER_BYTES, 8)) {
        memcpy(g_fov_tramp, site, 8);
        g_fov_tramp[8] = 0xE9;
        *(int32_t *)(g_fov_tramp + 9) = (int32_t)(((uint32_t)FOV_GETTER + 8) - ((uint32_t)(uintptr_t)g_fov_tramp + 13));
    } else {
        logf("field of view: the getter at %08X isn't as expected (%02X %02X %02X); field of view rows off", FOV_GETTER, site[0], site[1], site[2]);
        return;
    }
    DWORD old;
    if (!VirtualProtect(site, 5, PAGE_EXECUTE_READWRITE, &old)) return;
    site[0] = 0xE9;
    *(int32_t *)(site + 1) = (int32_t)((uint32_t)(uintptr_t)fov_thunk - ((uint32_t)FOV_GETTER + 5));
    VirtualProtect(site, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), site, 5);
    g_fov_hooked = 1;
    logf("field of view: getter %08X wrapped", FOV_GETTER);
}
static int l_set_fov(lua_State *s)
{
    float m = (float)luaL_checknumber(s, 1);
    if (!(m > 0.05f && m < 5.0f)) m = 1.0f;
    g_fov_mult = m;
    lua_pushboolean(s, g_fov_hooked);
    return 1;
}

// ------------------------------------------------------------------ settings, log, callbacks
// setting(name, default): mod.ini [settings], typed like the default.
static int l_setting(lua_State *s)
{
    const char *name = luaL_checkstring(s, 1);
    char v[512];
    GetPrivateProfileStringA("settings", name, "\x01", v, sizeof v, g_ini);
    if (v[0] == 1) { lua_settop(s, 2); return 1; }
    char *c = strchr(v, ';'); if (c) *c = 0;   // a comment after the value
    size_t n = strlen(v); while (n && (v[n - 1] == ' ' || v[n - 1] == '\t')) v[--n] = 0;
    switch (lua_type(s, 2)) {
    case LUA_TNUMBER: {
        char *end; double d = strtod(v, &end);
        if (end == v) { lua_settop(s, 2); return 1; }
        if (d == (double)(lua_Integer)d && !strpbrk(v, ".eE")) lua_pushinteger(s, (lua_Integer)d); else lua_pushnumber(s, d);
        return 1;
    }
    case LUA_TBOOLEAN: lua_pushboolean(s, !_stricmp(v, "true") || !strcmp(v, "1") || !_stricmp(v, "yes")); return 1;
    default: lua_pushstring(s, v); return 1;
    }
}
static int l_log(lua_State *s)
{
    int n = lua_gettop(s);   // (before the buffer, which may take a stack slot)
    luaL_Buffer b; luaL_buffinit(s, &b);
    for (int i = 1; i <= n; i++) {
        if (i > 1) luaL_addchar(&b, ' ');
        luaL_tolstring(s, i, NULL); luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
    logf("%s", lua_tostring(s, -1));
    return 0;
}
static int l_on_frame(lua_State *s)
{
    luaL_checktype(s, 1, LUA_TFUNCTION);
    lua_getfield(s, LUA_REGISTRYINDEX, "wml_frames");
    lua_pushvalue(s, 1);
    lua_rawseti(s, -2, (lua_Integer)lua_rawlen(s, -2) + 1);
    return 0;
}
static int l_hook(lua_State *s)
{
    return luaL_error(s, "wml.hook isn't available on Saints Row 2 yet (address %p)", (void *)(uintptr_t)((uint32_t)luaL_optinteger(s, 1, 0)));
}

// Count native gun discharges, including the automatic loop and infinite ammo.
// Capture player-caused weapon damage for the next update, after reactions run.
static volatile LONG g_shot_watch, g_fire_watch, g_shots;
static volatile LONG g_fire_lock;
static uint32_t g_fire_victims[32];
static unsigned g_fire_count;
static uint32_t g_discharge_resume = 0x009BE6F6;
static uint32_t g_damage_resume = 0x009847A6;
static int g_discharge_hook, g_damage_hook;
static volatile LONG g_block_idle, g_rest_pose;
static uint32_t g_idle_resume = 0x0096FCA6;
static int g_idle_hook, g_pose_hook;
typedef uint32_t (__stdcall *pose_combine_t)(uint32_t, uint32_t, uint32_t);
static pose_combine_t g_pose_original;

static __declspec(naked) void idle_thunk(void)
{
    __asm {
        pushfd
        cmp dword ptr [g_block_idle], 0
        je original
        cmp ecx, dword ptr ds:[021703D4h]
        jne original
        push eax
        mov eax, [esp + 12]
        cmp eax, 539h
        jae keep
        imul eax, 12
        test byte ptr [eax + 0E90E48h], 4
        jnz block
        mov eax, [eax + 0E90E40h]
        test eax, eax
        jz keep
        cmp dword ptr [eax], 656C6469h  // "idle"
        jne keep
        cmp byte ptr [eax + 4], 20h
        jne keep
    block:
        pop eax
        popfd
        xor eax, eax
        ret
    keep:
        pop eax
    original:
        popfd
        sub esp, 52Ch
        jmp dword ptr [g_idle_resume]
    }
}

typedef struct {
    uint32_t local_matrix[128][12];
    uint32_t flags[128];
    uint32_t matrices, flag_array, count;
} rest_snapshot_t;

// BEGIN verified neutral rig math (also compiled by offline tests).
static int neutral_rest_matrix(const float parent[12], const float parent_bind[3],
                               const float child_bind[3], float output[12])
{
    float delta[3];
    for (int axis = 0; axis < 3; ++axis) {
        delta[axis] = parent_bind[axis] - child_bind[axis];
        if (delta[axis] != delta[axis] || delta[axis] < -10000.0f || delta[axis] > 10000.0f) return 0;
    }
    memcpy(output, parent, 9 * sizeof(float));
    for (int axis = 0; axis < 3; ++axis) {
        float value = parent[9 + axis] + parent[axis] * delta[0]
                    + parent[3 + axis] * delta[1] + parent[6 + axis] * delta[2];
        if (value != value || value < -10000000.0f || value > 10000000.0f) return 0;
        output[9 + axis] = value;
    }
    return 1;
}
// END verified neutral rig math.

static int save_rest_pose(uint32_t animator, rest_snapshot_t *saved)
{
    if (!g_rest_pose) return 0;
    __try {
        uint32_t p = *(uint32_t *)0x021703D4;
        if (!p || *(uint8_t *)(p + 0x595) || *(uint32_t *)(p + 0x18D4)) return 0;
        uint32_t owner = *(uint32_t *)(p + 0x5E0);
        if (!owner || owner == 0xFFFFFFFF) return 0;
        uint32_t id = *(uint32_t *)owner;
        if (id >= 0x80000000 || animator != 0x0340D240 + (id % 190) * 0x5E8) return 0;
        uint32_t map = *(uint32_t *)(animator + 0x228);
        uint32_t rig = *(uint32_t *)(animator + 0x18);
        saved->matrices = *(uint32_t *)(animator + 4);
        saved->flag_array = *(uint32_t *)(animator + 8);
        if (!map || !rig || !saved->matrices || !saved->flag_array ||
            saved->matrices == *(uint32_t *)animator) return 0;
        saved->count = *(uint32_t *)(map + 4);
        uint32_t rig_count = *(uint32_t *)(rig + 0x24);
        uint32_t bones = *(uint32_t *)(rig + 0x38);
        if (saved->count < 20 || saved->count > 128 || !bones || rig_count < saved->count || rig_count > 128) return 0;
        float neutral[128][12];
        memcpy(neutral[0], (void *)saved->matrices, 48);
        // CE9990/CE9D0F's neutral-parent branch: inherit the actual parent
        // basis, including the player's world transform, and cancel the rig's
        // inverse bind origins. Zero translations collapse the skinned body.
        // Compute and validate the whole rig before touching game memory.
        for (uint32_t i = 1; i < saved->count; ++i) {
            int bone = *(int16_t *)(map + 8 + i * 2);
            if (bone < 0 || (uint32_t)bone >= rig_count) return 0;
            int parent_bone = *(int32_t *)(bones + bone * 36 + 0x1C);
            if (parent_bone < 0 || (uint32_t)parent_bone >= rig_count) return 0;
            int parent = *(int16_t *)(map + 0x108 + parent_bone * 2);
            if (parent < 0 || (uint32_t)parent >= i ||
                *(int16_t *)(map + 8 + parent * 2) != parent_bone) return 0;
            if (!neutral_rest_matrix(neutral[parent], (float *)(bones + parent_bone * 36 + 4),
                                     (float *)(bones + bone * 36 + 4), neutral[i])) return 0;
            memcpy(saved->local_matrix[i], (void *)(saved->matrices + i * 48), 48);
            saved->flags[i] = *(uint32_t *)(saved->flag_array + i * 12);
        }
        for (uint32_t i = 1; i < saved->count; ++i) {
            memcpy((void *)(saved->matrices + i * 48), neutral[i], 48);
            // Local transform valid; force the native skin transform to rebuild.
            *(uint32_t *)(saved->flag_array + i * 12) = (saved->flags[i] & ~2u) | 1u;
        }
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}

static uint32_t __stdcall rest_pose_thunk(uint32_t animator, uint32_t levels, uint32_t threshold)
{
    rest_snapshot_t saved;
    int changed = save_rest_pose(animator, &saved);
    uint32_t result;
    __try {
        result = g_pose_original(animator, levels, threshold);
    } __finally {
        if (changed) {
            for (uint32_t i = 1; i < saved.count; ++i) {
                memcpy((void *)(saved.matrices + i * 48), saved.local_matrix[i], 48);
                *(uint32_t *)(saved.flag_array + i * 12) = saved.flags[i];
            }
        }
    }
    return result;
}

static __declspec(naked) void discharge_thunk(void)
{
    __asm {
        pushfd
        cmp dword ptr [g_shot_watch], 0
        je original
        push eax
        mov eax, dword ptr ds:[021703D4h]
        test eax, eax
        jz done
        cmp eax, [esp + 16]     // entry [esp+8]: shooter
        jne done
        lock inc dword ptr [g_shots]
    done:
        pop eax
    original:
        popfd
        push ebp
        mov ebp, esp
        and esp, -16
        jmp dword ptr [g_discharge_resume]
    }
}

static void __cdecl queue_fire_hit(uint32_t attacker, uint32_t victim, uint32_t amount, uint32_t weapon)
{
    if (!g_fire_watch || !attacker || attacker != *(uint32_t *)0x021703D4 || !victim ||
        victim == attacker || !weapon || amount == 0 || amount >= 0x7F800000) return;
    __try {
        uint32_t base = *(uint32_t *)0x022D7BCC;
        uint32_t count = *(uint32_t *)0x022D7BD0;
        uint32_t offset = weapon - base;
        if (!base || weapon < base || offset % 0x498 || offset / 0x498 >= count) return;
        uint32_t handle = *(uint32_t *)(victim + 0x44);
        if (!handle || handle == 0xFFFFFFFF) return;
        if (InterlockedCompareExchange(&g_fire_lock, 1, 0)) return;
        unsigned i = 0;
        while (i < g_fire_count && g_fire_victims[i] != handle) ++i;
        if (i == g_fire_count && g_fire_count < ARRAYSIZE(g_fire_victims))
            g_fire_victims[g_fire_count++] = handle;
        InterlockedExchange(&g_fire_lock, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

static __declspec(naked) void damage_thunk(void)
{
    __asm {
        pushfd
        cmp dword ptr [g_fire_watch], 0
        je original
        pushad
        mov eax, esp
        push [eax + 52]       // entry [esp+16]: weapon
        push [eax + 44]       // entry [esp+8]: damage
        push [eax + 40]       // entry [esp+4]: victim
        push ecx              // attacker
        call queue_fire_hit
        add esp, 16
        popad
    original:
        popfd
        sub esp, 54Ch
        jmp dword ptr [g_damage_resume]
    }
}

static int patch_entry(uint32_t address, const uint8_t expected[6], void *hook)
{
    uint8_t *site = (uint8_t *)address;
    DWORD old;
    if (memcmp(site, expected, 6) || !VirtualProtect(site, 6, PAGE_EXECUTE_READWRITE, &old))
        return 0;
    site[0] = 0xE9;
    *(int32_t *)(site + 1) = (int32_t)((uint32_t)(uintptr_t)hook - (address + 5));
    site[5] = 0x90;
    VirtualProtect(site, 6, old, &old);
    FlushInstructionCache(GetCurrentProcess(), site, 6);
    return 1;
}

static void hook_combat(void)
{
    static const uint8_t discharge[] = { 0x55, 0x8B, 0xEC, 0x83, 0xE4, 0xF0 };
    static const uint8_t damage[] = { 0x81, 0xEC, 0x4C, 0x05, 0x00, 0x00 };
    g_discharge_hook = patch_entry(0x009BE6F0, discharge, discharge_thunk);
    g_damage_hook = patch_entry(0x009847A0, damage, damage_thunk);
    static const uint8_t idle[] = { 0x81, 0xEC, 0x2C, 0x05, 0x00, 0x00 };
    g_idle_hook = patch_entry(0x0096FCA0, idle, idle_thunk);
    static const uint8_t pose[] = { 0x83, 0xEC, 0x48, 0x53, 0x8B, 0x5C, 0x24, 0x50 };
    uint8_t *site = (uint8_t *)0x00CE7D00;
    if (!memcmp(site, pose, sizeof pose)) {
        uint8_t *trampoline = VirtualAlloc(NULL, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        DWORD old;
        if (trampoline && VirtualProtect(site, 8, PAGE_EXECUTE_READWRITE, &old)) {
            memcpy(trampoline, site, 8);
            trampoline[8] = 0xE9;
            *(int32_t *)(trampoline + 9) = (int32_t)((site + 8) - (trampoline + 13));
            g_pose_original = (pose_combine_t)trampoline;
            site[0] = 0xE9;
            *(int32_t *)(site + 1) = (int32_t)((uint8_t *)rest_pose_thunk - (site + 5));
            memset(site + 5, 0x90, 3);
            VirtualProtect(site, 8, old, &old);
            FlushInstructionCache(GetCurrentProcess(), site, 8);
            g_pose_hook = 1;
        } else if (trampoline) VirtualFree(trampoline, 0, MEM_RELEASE);
    }
    logf("combat events: gun discharge %s, weapon damage %s",
        g_discharge_hook ? "ready" : "unavailable", g_damage_hook ? "ready" : "unavailable");
    logf("preview guards: idle suppression %s, customization rest pose %s",
        g_idle_hook ? "ready" : "unavailable", g_pose_hook ? "ready" : "unavailable");
}

static int l_preview_mode(lua_State *s)
{
    InterlockedExchange(&g_block_idle, g_idle_hook && lua_toboolean(s, 1));
    InterlockedExchange(&g_rest_pose, g_pose_hook && lua_toboolean(s, 2));
    lua_pushboolean(s, g_pose_hook);
    return 1;
}

static int l_shots(lua_State *s)
{
    if (!g_discharge_hook) return 0;
    InterlockedExchange(&g_shot_watch, lua_toboolean(s, 1));
    lua_pushinteger(s, InterlockedExchange(&g_shots, 0));
    return 1;
}

static int l_fire_hits(lua_State *s)
{
    if (!g_damage_hook) return 0;
    int enabled = lua_toboolean(s, 1);
    InterlockedExchange(&g_fire_watch, enabled);
    if (InterlockedCompareExchange(&g_fire_lock, 1, 0)) return 0;
    uint32_t victims[ARRAYSIZE(g_fire_victims)];
    unsigned count = enabled ? g_fire_count : 0;
    memcpy(victims, g_fire_victims, count * sizeof *victims);
    g_fire_count = 0;
    InterlockedExchange(&g_fire_lock, 0);
    lua_createtable(s, count, 0);
    for (unsigned i = 0; i < count; ++i) {
        lua_pushinteger(s, victims[i]);
        lua_rawseti(s, -2, i + 1);
    }
    return 1;
}

#include "gangdots_host.h"
#include "gait_host.h"

static void start_lua(void)
{
    L = luaL_newstate();
    luaL_openlibs(L);
    lua_newtable(L); lua_setfield(L, LUA_REGISTRYINDEX, "wml_frames");

    static const luaL_Reg api[] = {
        { "log", l_log }, { "setting", l_setting },
        { "read_u8", l_read_u8 }, { "read_u16", l_read_u16 }, { "read_u32", l_read_u32 }, { "read_f32", l_read_f32 },
        { "write_u8", l_write_u8 }, { "write_u16", l_write_u16 }, { "write_u32", l_write_u32 }, { "write_f32", l_write_f32 },
        { "key_down", l_key_down }, { "key_pressed", l_key_pressed }, { "take_key", l_take_key },
        { "force_key", l_noop }, { "mouse_look", l_noop }, { "set_look", l_noop },
        { "on_frame", l_on_frame }, { "hook", l_hook },
        { "script", l_script }, { "vint", l_vint }, { "call", l_call }, { "callx", l_callx },
        { "buffer", l_buffer }, { "read_string", l_read_string }, { "patch", l_patch },
        { "pad", l_pad }, { "pad_filter", l_pad_filter }, { "pad_inject", l_pad_inject }, { "pad_debug", l_pad_debug }, { "sticks", l_sticks }, { "pad_source", l_pad_source }, { "set_fov", l_set_fov },
        { "f2u", l_f2u }, { "u2f", l_u2f },
        { "gun_shots", l_shots }, { "fire_hits", l_fire_hits },
        { "preview_mode", l_preview_mode },
        { "menu_capture", l_menu_capture }, { "grab_remap", l_grab_remap },
        { "gang_dots", l_gang_dots },
        { "sr1_gait", l_sr1_gait },
        { NULL, NULL }
    };
    luaL_newlib(L, api);
    lua_pushstring(L, g_mod_folder); lua_setfield(L, -2, "mod_folder");
    lua_pushstring(L, "SR Tweak Menu"); lua_setfield(L, -2, "mod_name");
    lua_pushstring(L, "sr2"); lua_setfield(L, -2, "game");
    lua_setglobal(L, "wml");

    // require() finds the menu's files in its own folder.
    lua_getglobal(L, "package");
    lua_pushfstring(L, "%s\\?.lua", g_mod_folder);
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);

    char main_path[MAX_PATH];
    _snprintf_s(main_path, sizeof main_path, _TRUNCATE, "%s\\main.lua", g_mod_folder);
    if (luaL_loadfile(L, main_path) != LUA_OK || lua_pcall(L, 0, 0, 0) != LUA_OK) {
        logf("menu failed to load: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
        g_lua_failed = 1;
        return;
    }
    logf("menu loaded from %s", g_mod_folder);
}

// ------------------------------------------------------------------ per frame (main thread)
static void __cdecl on_frame(void)
{
    if (g_lua_failed) return;
    g_frame_count++;
    if (!L) { logf("first frame: starting Lua"); start_lua(); if (g_lua_failed) return; }
    poll_keys();
    lua_getfield(L, LUA_REGISTRYINDEX, "wml_frames");
    lua_Integer n = (lua_Integer)lua_rawlen(L, -1);
    for (lua_Integer i = 1; i <= n; i++) {
        lua_rawgeti(L, -1, i);
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
            if (g_menu_capture) {
                g_pad_all = 1;
                static const char warning[] = "SR TWEAK MENU\nMenu update failed. Input captured for safety.\nPress F5 to close the menu.";
                EnterCriticalSection(&g_lock);
                memcpy(g_mailbox + 0x40, warning, sizeof warning - 1);
                mailbox_set(MAILBOX + 0x14, 4, sizeof warning - 1);
                LeaveCriticalSection(&g_lock);
            }
            static char last[512];
            const char *e = lua_tostring(L, -1);
            if (e && strncmp(last, e, sizeof last - 1)) { strncpy_s(last, sizeof last, e, _TRUNCATE); logf("frame error: %s", e); }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
}

// ------------------------------------------------------------------ drawing (main thread, 2D pass)
static void text_colour(int r, int g, int b, int a) { ((void (__cdecl *)(int, int, int, int))TEXT_COLOUR)(r, g, b, a); }
static void text_print(const char *text, int x, int y, int font)
{
    __asm {
        pushad
        mov edi, font
        mov esi, text
        push y
        push x
        mov eax, TEXT_PRINT
        call eax
        add esp, 8
        popad
    }
}
static int font_handle(int which) { return which == 6 ? *(int *)FONT_SMALL_PTR : *(int *)FONT_MEDIUM_PTR; }

// Where 1280x720 layout x=0 is on screens wider than 16:9.
static int left_edge(void)
{
    uint32_t w = *(uint32_t *)VINT_RES_X, h = *(uint32_t *)VINT_RES_Y;
    if (!w || !h) return 0;
    float vw = (float)w / (float)h * 720.0f;
    return vw > 1280.0f ? (int)((vw - 1280.0f) / 2.0f) : 0;
}

static void draw_menu(void)
{
    static char text[8192 + 1];
    EnterCriticalSection(&g_lock);
    uint32_t n = mailbox_get(MAILBOX + 0x14, 4);
    if (n > 8192) n = 8192;
    memcpy(text, g_mailbox + 0x40, n);
    LeaveCriticalSection(&g_lock);
    text[n] = 0;
    if (!n) return;

    int font = font_handle(g_ov_font), x0 = left_edge() + g_ov_x, y = g_ov_y, line_no = 0;
    __try {
        for (char *line = text, *next; line; line = next, line_no++) {
            next = strchr(line, '\n');
            if (next) *next++ = 0;
            if (*line) {
                int r = 235, g = 235, b = 235;
                if (line_no == 0) { r = 255; g = 205; b = 60; }                 // title
                else if (line_no == 1) { r = 150; g = 200; b = 255; }           // tabs
                else if (line[0] == '>' && line[1] == ' ') { r = 255; g = 205; b = 60; }  // cursor row / page title
                else if (!strncmp(line, "  --", 4)) { r = 160; g = 160; b = 160; }
                text_colour(0, 0, 0, 200);
                text_print(line, x0 + 2, y + 2, font);
                text_colour(r, g, b, 255);
                text_print(line, x0, y, font);
            }
            y += g_ov_line;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        static int told;
        if (!told++) logf("drawing the menu crashed; overlay off");
        g_ov_font = -1;
    }
}
static void __cdecl on_draw(void) { if (g_ov_font >= 0) draw_menu(); }

// ------------------------------------------------------------------ thunks and patching
// Reached by the game's `call`: keep every register and flag, run ours, then
// continue into whatever the call went to before (it returns to the game).
static __declspec(naked) void frame_thunk(void)
{
    __asm {
        pushad
        pushfd
        call on_frame
        popfd
        popad
        call dword ptr [g_frame_prev]
        pushad
        pushfd
        call after_input_update
        popfd
        popad
        ret
    }
}
static __declspec(naked) void draw_thunk(void)
{
    __asm {
        pushad
        pushfd
        call on_draw
        popfd
        popad
        jmp dword ptr [g_draw_prev]
    }
}

static uint32_t call_target(uint32_t site) { return site + 5 + *(int32_t *)(site + 1); }
static int patch_call(uint32_t site, void *to, uint32_t *prev)
{
    if (*(uint8_t *)site != 0xE8) { logf("%08X isn't a call; not hooked", site); return 0; }
    DWORD old;
    if (!VirtualProtect((void *)(uintptr_t)site, 5, PAGE_EXECUTE_READWRITE, &old)) return 0;
    *prev = call_target(site);
    *(int32_t *)(site + 1) = (int32_t)((uint32_t)(uintptr_t)to - (site + 5));
    VirtualProtect((void *)(uintptr_t)site, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), (void *)(uintptr_t)site, 5);
    logf("hooked %08X (it called %08X)", site, *prev);
    return 1;
}

// Juiced Patch hooks both calls from its WinMain hook; ours go on top, so
// we wait for it (up to 20 s). Without Juiced (the game's own DFEngine.dll,
// which lacks Juiced's API export) we hook the game straight away.
static DWORD WINAPI installer(LPVOID unused)
{
    (void)unused;
    HMODULE engine = GetModuleHandleA("DFEngine.dll");
    if (!engine || !GetProcAddress(engine, "RegisterVintLuaHookString")) {
        logf("Juiced Patch isn't installed; hooking the game directly");
        hook_combat();
        patch_call(DRAW_CALL_SITE, (void *)draw_thunk, &g_draw_prev);
        patch_call(FRAME_CALL_SITE, (void *)frame_thunk, &g_frame_prev);
        hook_pad_import();
        patch_call(PAD_POLL_SITE_X, (void *)pad_poll_thunk_x, &g_poll_prev_x);
        patch_call(PAD_POLL_SITE_D, (void *)pad_poll_thunk_d, &g_poll_prev_d);
        hook_fov();
        return 0;
    }
    int waited = 0;
    for (; waited < 400; waited++) {
        if (call_target(FRAME_CALL_SITE) != FRAME_CALL_GAME && call_target(DRAW_CALL_SITE) != DRAW_CALL_GAME) break;
        Sleep(50);
    }
    logf(waited < 400 ? "Juiced's hooks found after %d ms" : "Juiced's hooks not found after %d ms; hooking the game directly", waited * 50);
    hook_combat();
    patch_call(DRAW_CALL_SITE, (void *)draw_thunk, &g_draw_prev);
    patch_call(FRAME_CALL_SITE, (void *)frame_thunk, &g_frame_prev);
    // (after Juiced's own: its XInput and field of view hooks are wrapped, not replaced)
    hook_pad_import();
    patch_call(PAD_POLL_SITE_X, (void *)pad_poll_thunk_x, &g_poll_prev_x);
    patch_call(PAD_POLL_SITE_D, (void *)pad_poll_thunk_d, &g_poll_prev_d);
    hook_fov();
    return 0;
}

// ------------------------------------------------------------------ DirectInput proxy
static const GUID KEYBOARD_GUID = { 0x6F1D2B61, 0xD5A0, 0x11CF, { 0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
typedef HRESULT (WINAPI *create_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);
typedef HRESULT (WINAPI *create_device_t)(void *self, REFGUID guid, void **device, void *outer);
typedef HRESULT (WINAPI *get_state_t)(void *self, DWORD size, void *data);
typedef HRESULT (WINAPI *get_data_t)(void *self, DWORD item_size, void *items, DWORD *count, DWORD flags);

// The A and W interfaces have vtables of their own: up to 4 of each kept.
typedef struct { void **vt; void *orig; } slot_t;
static slot_t g_create_device[4], g_get_state[4], g_get_data[4];
static void *g_keyboards[8];

static void *orig_for(slot_t *slots, void **vt)
{
    for (int i = 0; i < 4; i++) if (slots[i].vt == vt) return slots[i].orig;
    return NULL;
}
static void hook_vtable(slot_t *slots, void **vt, int index, void *fn)
{
    if (orig_for(slots, vt)) return;
    for (int i = 0; i < 4; i++) if (!slots[i].vt) {
        DWORD old;
        VirtualProtect(&vt[index], sizeof(void *), PAGE_EXECUTE_READWRITE, &old);
        slots[i].orig = vt[index];
        slots[i].vt = vt;
        vt[index] = fn;
        VirtualProtect(&vt[index], sizeof(void *), old, &old);
        return;
    }
}
static int is_keyboard(void *dev)
{
    for (int i = 0; i < 8; i++) if (g_keyboards[i] == dev) return 1;
    return 0;
}

static HRESULT WINAPI my_get_state(void *self, DWORD size, void *data)
{
    get_state_t orig = (get_state_t)orig_for(g_get_state, *(void ***)self);
    HRESULT hr = orig(self, size, data);
    if (SUCCEEDED(hr) && size == 256 && data) {
        uint8_t *keys = (uint8_t *)data;
        for (int k = 0; k < 256; k++) if (g_taken[k]) keys[k] = 0;
    }
    return hr;
}
// Buffered keyboard data: taken keys' presses are dropped (releases still
// go through, so nothing sticks down).
static HRESULT WINAPI my_get_data(void *self, DWORD item_size, void *items, DWORD *count, DWORD flags)
{
    get_data_t orig = (get_data_t)orig_for(g_get_data, *(void ***)self);
    HRESULT hr = orig(self, item_size, items, count, flags);
    if (SUCCEEDED(hr) && items && count && !(flags & 1 /* DIGDD_PEEK */) && is_keyboard(self)) {
        uint8_t *base = (uint8_t *)items;
        DWORD kept = 0;
        for (DWORD i = 0; i < *count; i++) {
            uint8_t *it = base + i * item_size;
            DWORD ofs = *(DWORD *)it, val = *(DWORD *)(it + 4);
            if (ofs < 256 && g_taken[ofs] && (val & 0x80)) continue;
            if (kept != i) memmove(base + kept * item_size, it, item_size);
            kept++;
        }
        *count = kept;
    }
    return hr;
}
static HRESULT WINAPI my_create_device(void *self, REFGUID guid, void **device, void *outer)
{
    create_device_t orig = (create_device_t)orig_for(g_create_device, *(void ***)self);
    HRESULT hr = orig(self, guid, device, outer);
    if (SUCCEEDED(hr) && device && *device) {
        void **vt = *(void ***)*device;
        hook_vtable(g_get_state, vt, 9, (void *)my_get_state);
        hook_vtable(g_get_data, vt, 10, (void *)my_get_data);
        if (IsEqualGUID(guid, &KEYBOARD_GUID)) {
            for (int i = 0; i < 8; i++) if (!g_keyboards[i]) { g_keyboards[i] = *device; break; }
            logf("keyboard device wrapped");
        }
    }
    return hr;
}

// Loaded as an .asi by an ASI loader (which is dinput8.dll itself): the
// game's DirectInput8Create import is pointed here instead, and passed on
// to what it pointed to before (the loader's, then the real one).
static create_t g_di8_next;

HRESULT WINAPI proxy_DirectInput8Create(HINSTANCE inst, DWORD version, REFIID riid, LPVOID *out, LPUNKNOWN outer)
{
    static create_t real;
    if (!real && g_di8_next) real = g_di8_next;
    if (!real) {
        char path[MAX_PATH];
        GetSystemDirectoryA(path, MAX_PATH);
        strcat_s(path, MAX_PATH, "\\dinput8.dll");
        HMODULE m = LoadLibraryA(path);
        real = m ? (create_t)GetProcAddress(m, "DirectInput8Create") : NULL;
        if (!real) { logf("couldn't load the real dinput8.dll"); return E_FAIL; }
    }
    HRESULT hr = real(inst, version, riid, out, outer);
    if (SUCCEEDED(hr) && out && *out) hook_vtable(g_create_device, *(void ***)*out, 3, (void *)my_create_device);
    return hr;
}

// The game's import slot for dinput8.dll's DirectInput8Create, found in
// SR2_pc.exe's import table (NULL if it hasn't one).
static void **di8_import_slot(void)
{
    uint8_t *base = (uint8_t *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir.VirtualAddress) return NULL;
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
        if (_stricmp((char *)(base + d->Name), "dinput8.dll")) continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        IMAGE_THUNK_DATA *slots = (IMAGE_THUNK_DATA *)(base + d->FirstThunk);
        for (; names->u1.AddressOfData; names++, slots++) {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            IMAGE_IMPORT_BY_NAME *n = (IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData);
            if (!strcmp((char *)n->Name, "DirectInput8Create")) return (void **)&slots->u1.Function;
        }
    }
    return NULL;
}
static void hook_di8_import(void)
{
    void **slot = di8_import_slot();
    if (!slot || !*slot) { logf("no DirectInput8Create import found; the menu can't keep keys from the game"); return; }
    if (*slot == (void *)proxy_DirectInput8Create) return;
    DWORD old;
    if (!VirtualProtect(slot, sizeof *slot, PAGE_READWRITE, &old)) { logf("couldn't unprotect the DirectInput8Create import"); return; }
    g_di8_next = (create_t)*slot;
    *slot = (void *)proxy_DirectInput8Create;
    VirtualProtect(slot, sizeof *slot, old, &old);
    logf("loaded as an .asi: DirectInput8Create import at %p wrapped (it went to %p)", (void *)slot, (void *)g_di8_next);
}

// ------------------------------------------------------------------ entry
static int ini_int(const char *key, int def) { return (int)GetPrivateProfileIntA("settings", key, def, g_ini); }
static int ini_bool(const char *key)
{
    char v[16];
    GetPrivateProfileStringA("settings", key, "", v, sizeof v, g_ini);
    return !_stricmp(v, "true") || !strcmp(v, "1") || !_stricmp(v, "yes");
}
static void patch_code(uint32_t at, const void *bytes, size_t n)
{
    DWORD old;
    if (!VirtualProtect((void *)(uintptr_t)at, n, PAGE_EXECUTE_READWRITE, &old)) return;
    memcpy((void *)(uintptr_t)at, bytes, n);
    VirtualProtect((void *)(uintptr_t)at, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), (void *)(uintptr_t)at, n);
}

// Settings that act before the menu's Lua starts (it starts on the first
// frame): mod.ini skip_intro and higher_max_speed.
static void start_up_patches(void)
{
    if (ini_bool("skip_intro")) {
        // The boot code waits on 0x00F9F46E while the logo movies play: don't
        // set it. And the legal-screen state machine's first state jumps
        // straight to its last.
        static const uint8_t nops[6] = { 0x90, 0x90, 0x90, 0x90, 0x90, 0x90 };
        static const uint32_t last_state = 0x0068C596;
        patch_code(0x005207B4, nops, 6);
        patch_code(0x0068C740, &last_state, 4);
        logf("skip intro: on");
    }
    if (ini_bool("higher_max_speed")) {
        // vehicles.xtbl's top speeds aren't capped at 100 mph as they load.
        static const uint8_t nop2[2] = { 0x90, 0x90 };
        patch_code(0x00AEB541, nop2, 2);
        patch_code(0x00AEB5A2, nop2, 2);
        logf("higher max speed: on");
    }
}

BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID unused)
{
    (void)unused;
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(self);
    InitializeCriticalSection(&g_lock);

    GetModuleFileNameA(NULL, g_game_dir, MAX_PATH);
    char *slash = strrchr(g_game_dir, '\\'); if (slash) *slash = 0;
    _snprintf_s(g_root, MAX_PATH, _TRUNCATE, "%s\\TweakMenu", g_game_dir);
    _snprintf_s(g_mod_folder, MAX_PATH, _TRUNCATE, "%s\\SRTweakMenu", g_root);
    _snprintf_s(g_ini, MAX_PATH, _TRUNCATE, "%s\\mod.ini", g_mod_folder);
    _snprintf_s(g_log_path, MAX_PATH, _TRUNCATE, "%s\\wml.log", g_root);
    CreateDirectoryA(g_root, NULL);
    g_log = _fsopen(g_log_path, "w", _SH_DENYNO);   // (readable while the game runs)
    logf("SR2 Tweak Menu host started in %s", g_game_dir);

    // As scripts\SRTweakMenu.asi (next to an ASI loader that is the game's
    // dinput8.dll) rather than as dinput8.dll itself.
    char self_path[MAX_PATH];
    DWORD self_len = GetModuleFileNameA(self, self_path, MAX_PATH);
    if (self_len > 4 && !_stricmp(self_path + self_len - 4, ".asi")) hook_di8_import();

    g_ov_x = ini_int("overlay_x", g_ov_x);
    g_ov_y = ini_int("overlay_y", g_ov_y);
    g_ov_line = ini_int("overlay_line", g_ov_line);
    g_ov_font = ini_int("overlay_font", g_ov_font);

    // Only the Steam/GOG executable has these calls where we expect them.
    if (*(uint8_t *)FRAME_CALL_SITE != 0xE8 || *(uint8_t *)DRAW_CALL_SITE != 0xE8) {
        logf("this isn't the Saints Row 2 executable the menu knows; menu off (input passes through)");
        return TRUE;
    }
    start_up_patches();
    HANDLE t = CreateThread(NULL, 0, installer, NULL, 0, NULL);
    if (t) CloseHandle(t);
    return TRUE;
}
