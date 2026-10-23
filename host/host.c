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
    if (!mem_read(a, &v, n)) return luaL_error(s, "bad read at %08X", a);
    lua_pushinteger(s, v);
    return 1;
}
static int l_read_u8(lua_State *s)  { return l_read(s, 1); }
static int l_read_u16(lua_State *s) { return l_read(s, 2); }
static int l_read_u32(lua_State *s) { return l_read(s, 4); }
static int l_read_f32(lua_State *s)
{
    uint32_t a = check_addr(s, 1); float f;
    if (!mem_read(a, &f, 4)) return luaL_error(s, "bad read at %08X", a);
    lua_pushnumber(s, f);
    return 1;
}
static int l_write(lua_State *s, int n)
{
    uint32_t a = check_addr(s, 1), v = (uint32_t)luaL_checkinteger(s, 2);
    if (in_mailbox(a, n)) { mailbox_set(a, n, v); return 0; }
    if (!mem_write(a, &v, n)) return luaL_error(s, "bad write at %08X", a);
    return 0;
}
static int l_write_u8(lua_State *s)  { return l_write(s, 1); }
static int l_write_u16(lua_State *s) { return l_write(s, 2); }
static int l_write_u32(lua_State *s) { return l_write(s, 4); }
static int l_write_f32(lua_State *s)
{
    uint32_t a = check_addr(s, 1); float f = (float)luaL_checknumber(s, 2);
    if (!mem_write(a, &f, 4)) return luaL_error(s, "bad write at %08X", a);
    return 0;
}
static int l_f2u(lua_State *s) { float f = (float)luaL_checknumber(s, 1); uint32_t u; memcpy(&u, &f, 4); lua_pushinteger(s, u); return 1; }
static int l_u2f(lua_State *s) { uint32_t u = (uint32_t)luaL_checkinteger(s, 1); float f; memcpy(&f, &u, 4); lua_pushnumber(s, f); return 1; }

// ------------------------------------------------------------------ game calls
// Runs code on the game's own Lua state (Lua 5.0, the mission scripts' one).
static int game_dostring(const char *code)
{
    void *state = *(void **)LUA_STATE_PTR;
    if (!state) return 0;
    __try {
        __asm {
            pushad
            mov esi, state
            mov eax, code
            mov edx, LUA_DOSTRING
            call edx
            popad
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return -1; }
    return 1;
}
static int l_script(lua_State *s)
{
    int r = game_dostring(luaL_checkstring(s, 1));
    if (r < 0) return luaL_error(s, "the game crashed running the script");
    lua_pushboolean(s, r == 1);
    return 1;
}

typedef uint32_t (__cdecl *cdecl8)(uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
static int call_guarded(uint32_t fn, const uint32_t *a, uint32_t *out)
{
    __try { *out = ((cdecl8)(uintptr_t)fn)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); return 1; }
    __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}
// A cdecl call with up to 8 integer arguments (extra ones are harmless: the
// caller cleans the stack). Functions taking arguments in registers need a
// thunk of their own.
static int l_call(lua_State *s)
{
    uint32_t fn = check_addr(s, 1), a[8] = { 0 }, r;
    int n = lua_gettop(s) - 1;
    if (n > 8) return luaL_error(s, "call: at most 8 arguments");
    for (int i = 0; i < n; i++) a[i] = (uint32_t)luaL_checkinteger(s, i + 2);
    if (!call_guarded(fn, a, &r)) return luaL_error(s, "call %08X crashed", fn);
    lua_pushinteger(s, r);
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

// Controller 1 through XInput: buttons, left trigger, right trigger (or nil).
typedef struct { DWORD packet; WORD buttons; BYTE lt, rt; SHORT lx, ly, rx, ry; } xstate_t;
typedef DWORD (WINAPI *xget_t)(DWORD, xstate_t *);
static xget_t g_xget;
static int l_pad(lua_State *s)
{
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
    return luaL_error(s, "wml.hook isn't available on Saints Row 2 yet (address %08X)", (uint32_t)luaL_optinteger(s, 1, 0));
}

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
        { "script", l_script }, { "call", l_call }, { "pad", l_pad }, { "f2u", l_f2u }, { "u2f", l_u2f },
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
        jmp dword ptr [g_frame_prev]
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
// we wait for it (up to 20 s: without Juiced we hook the game directly).
static DWORD WINAPI installer(LPVOID unused)
{
    (void)unused;
    int waited = 0;
    for (; waited < 400; waited++) {
        if (call_target(FRAME_CALL_SITE) != FRAME_CALL_GAME && call_target(DRAW_CALL_SITE) != DRAW_CALL_GAME) break;
        Sleep(50);
    }
    logf(waited < 400 ? "Juiced's hooks found after %d ms" : "Juiced's hooks not found after %d ms; hooking the game directly", waited * 50);
    patch_call(DRAW_CALL_SITE, (void *)draw_thunk, &g_draw_prev);
    patch_call(FRAME_CALL_SITE, (void *)frame_thunk, &g_frame_prev);
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

HRESULT WINAPI proxy_DirectInput8Create(HINSTANCE inst, DWORD version, REFIID riid, LPVOID *out, LPUNKNOWN outer)
{
    static create_t real;
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

// ------------------------------------------------------------------ entry
static int ini_int(const char *key, int def) { return (int)GetPrivateProfileIntA("settings", key, def, g_ini); }

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

    g_ov_x = ini_int("overlay_x", g_ov_x);
    g_ov_y = ini_int("overlay_y", g_ov_y);
    g_ov_line = ini_int("overlay_line", g_ov_line);
    g_ov_font = ini_int("overlay_font", g_ov_font);

    // Only the Steam/GOG executable has these calls where we expect them.
    if (*(uint8_t *)FRAME_CALL_SITE != 0xE8 || *(uint8_t *)DRAW_CALL_SITE != 0xE8) {
        logf("this isn't the Saints Row 2 executable the menu knows; menu off (input passes through)");
        return TRUE;
    }
    HANDLE t = CreateThread(NULL, 0, installer, NULL, 0, NULL);
    if (t) CloseHandle(t);
    return TRUE;
}
