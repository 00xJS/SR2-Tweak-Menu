/* Include after host.c's Lua/Windows headers, before start_lua().
 * Register {"gang_dots", l_gang_dots}. x86 MSVC, SR2 PC checked addresses.
 * Nothing is written to actors, mission markers, notoriety, or renderer tint.
 */
#ifndef SR2_GANGDOTS_HOST_H
#define SR2_GANGDOTS_HOST_H

static volatile LONG gd_enabled;
static int gd_installed;
typedef struct gd_colour_context { unsigned left, right; int active; } gd_colour_context;
static __declspec(thread) gd_colour_context gd_context;
#ifndef GD_MULTIPLAYER_FLAG
#define GD_MULTIPLAYER_FLAG ((unsigned char *)0x02528B48)
#endif

/* Native human team byte +111C: 0 Saints,1 Brotherhood,2 Ronin,3 Samedi,
 * 4 civilian,5 police,6 Ultor. Packed native vertices use AARRGGBB. */
static int gd_palette(int team, unsigned *left, unsigned *right)
{
    switch (team) {
    case 1: *left = *right = 0xFFFF2222; return 1;
    case 2: *left = *right = 0xFFFFFF00; return 1;
    case 3: *left = *right = 0xFF20DF20; return 1;
    case 5: *left = 0xFFFF2222; *right = 0xFF2277FF; return 1;
    case 6: *left = *right = 0xFFFF8800; return 1;
    default: return 0;
    }
}

static int gd_team_selected(unsigned human)
{
    unsigned left, right;
    /* Only singleplayer: preserve native multiplayer team/visibility rules. */
    return gd_enabled && *GD_MULTIPLAYER_FLAG != 1 &&
        gd_palette(*(signed char *)(human + 0x111C), &left, &right);
}

static int __cdecl gd_draw(unsigned human, const void *position, const unsigned *options)
{
    gd_colour_context previous;
    unsigned left, right;
    if (!gd_team_selected(human) ||
        !gd_palette(*(signed char *)(human + 0x111C), &left, &right)) return 0;
    previous = gd_context;
    gd_context.left = left; gd_context.right = right; gd_context.active = 1;
    /* This helper projects/clips the exact stock human blip and scales it with
     * the minimap. Draw hooks execute only within the native radar passes. */
    __try {
        ((void (__cdecl *)(const void *, unsigned, unsigned))0x0079EFC0)
            (position, options[0], options[1]);
    } __finally { gd_context = previous; }
    return 1;
}

static void __cdecl gd_colour_vertices(unsigned char *vertices)
{
    unsigned alpha;
    if (!gd_context.active) return;
    /* 28-byte native vertices: TL,TR,BL,BR. GPU interpolation provides an
     * actual left-to-right red/blue police gradient, rather than flashing. */
    /* Keep the stock radar fade/hide opacity. Native bitmap draw writes the
     * same current renderer alpha into all four vertices before this hook. */
    alpha = *(unsigned *)(vertices + 0x10) & 0xFF000000;
    *(unsigned *)(vertices + 0x10) = alpha | (gd_context.left & 0xFFFFFF);
    *(unsigned *)(vertices + 0x2C) = alpha | (gd_context.right & 0xFFFFFF);
    *(unsigned *)(vertices + 0x48) = alpha | (gd_context.left & 0xFFFFFF);
    *(unsigned *)(vertices + 0x64) = alpha | (gd_context.right & 0xFFFFFF);
}

static __declspec(naked) void gd_timer_hook(void)
{
    __asm {
        pushfd
        pushad
        push esi
        call gd_team_selected
        add esp, 4
        test eax, eax
        jz original
        popad
        popfd
        push 0079F266h
        ret
    original:
        popad
        popfd
        cmp dword ptr [esi+340h], 0
        push 0079F22Fh
        ret
    }
}

static __declspec(naked) void gd_human_hook(void)
{
    __asm {
        pushfd
        pushad
        lea eax, [esi+14h]
        push edi
        push eax
        push esi
        call gd_draw
        add esp, 12
        test eax, eax
        jz original
        popad
        popfd
        push 0079F45Ah
        ret
    original:
        popad
        popfd
        movsx eax, byte ptr [esi+111Ch]
        push 0079F37Dh
        ret
    }
}

static __declspec(naked) void gd_vehicle_hook(void)
{
    __asm {
        pushfd
        pushad
        /* Native pass has four pushed registers; argument pointer is at
         * original ESP+14h, now +14h+24h = +38h. */
        mov eax, [esp+38h]
        lea ecx, [ebp+14h]
        push eax
        push ecx
        push esi
        call gd_draw
        add esp, 12
        test eax, eax
        jz original
        popad
        popfd
        push 0079F64Ch
        ret
    original:
        popad
        popfd
        movsx eax, byte ptr [esi+111Ch]
        push 0079F54Eh
        ret
    }
}

static __declspec(naked) void gd_submit_hook(void)
{
    __asm {
        pushfd
        pushad
        push eax
        call gd_colour_vertices
        add esp, 4
        popad
        popfd
        /* Tail-call the original submit; preserve the CALL return address. */
        push 00D0A330h
        ret
    }
}

typedef struct gd_patch {
    unsigned address, length;
    unsigned char original[7], replacement[7];
    void *target;
    unsigned char opcode;
    int owned;
} gd_patch;
static gd_patch gd_patches[] = {
    {0x0079F228,7,{0x83,0xBE,0x40,0x03,0,0,0},{0},gd_timer_hook,0xE9,0},
    {0x0079F376,7,{0x0F,0xBE,0x86,0x1C,0x11,0,0},{0},gd_human_hook,0xE9,0},
    {0x0079F547,7,{0x0F,0xBE,0x86,0x1C,0x11,0,0},{0},gd_vehicle_hook,0xE9,0},
    {0x00B87F9B,5,{0xE8,0x90,0x23,0x18,0},{0},gd_submit_hook,0xE8,0}
};

static int gd_write(unsigned address, const void *bytes, unsigned length)
{
    DWORD protection, ignored;
    void *site = (void *)address;
    if (!VirtualProtect(site, length, PAGE_EXECUTE_READWRITE, &protection)) return 0;
    memcpy(site, bytes, length);
    FlushInstructionCache(GetCurrentProcess(), site, length);
    VirtualProtect(site, length, protection, &ignored);
    return 1;
}

/* Call only on game thread, before module unload. Never restore over a hook
 * installed later by another mod. Ordinary toggle-off needs no code writes. */
static void gd_shutdown(void)
{
    unsigned i;
    InterlockedExchange(&gd_enabled, 0);
    for (i = sizeof gd_patches / sizeof gd_patches[0]; i-- > 0;) {
        gd_patch *p = &gd_patches[i];
        if (p->owned && !memcmp((void *)p->address, p->replacement, p->length)) {
            if (gd_write(p->address, p->original, p->length)) p->owned = 0;
        }
    }
    gd_installed = 0;
}

static int gd_install(void)
{
    unsigned i;
    if (gd_installed) return 1;
    /* Verify every site before mutating anything. A conflict disables this
     * feature instead of overwriting Juiced/another mod or another EXE build. */
    for (i = 0; i < sizeof gd_patches / sizeof gd_patches[0]; ++i) {
        gd_patch *p = &gd_patches[i];
        if (memcmp((void *)p->address, p->original, p->length)) return 0;
        memset(p->replacement, 0x90, p->length);
        p->replacement[0] = p->opcode;
        *(int *)(p->replacement+1) = (int)((unsigned)p->target - (p->address+5));
    }
    for (i = 0; i < sizeof gd_patches / sizeof gd_patches[0]; ++i) {
        gd_patch *p = &gd_patches[i];
        if (!gd_write(p->address, p->replacement, p->length)) { gd_shutdown(); return 0; }
        p->owned = 1;
    }
    gd_installed = 1;
    return 1;
}

#ifndef GANGDOTS_NO_LUA
static int l_gang_dots(lua_State *s)
{
    int enabled = lua_toboolean(s, 1);
    if (enabled && !gd_install()) {
        lua_pushboolean(s, 0);
        lua_pushliteral(s, "Gang dots unavailable: unsupported executable or radar hook conflict");
        return 2;
    }
    InterlockedExchange(&gd_enabled, enabled);
    lua_pushboolean(s, 1);
    return 1;
}
#endif
#endif
