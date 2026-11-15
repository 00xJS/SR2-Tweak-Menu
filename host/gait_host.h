/* Include after host.c Windows/Lua headers. Register {"sr1_gait",l_sr1_gait}.
 * Call sg_shutdown before host unload, on the game thread. x86 MSVC only. */
#ifndef SR1_GAIT_HOST_H
#define SR1_GAIT_HOST_H
#include "gait_core.h"
static sg_state sg;
static unsigned sg_human,sg_actor;
static int sg_installed;
static unsigned char sg_patch[5];
static void *sg_trampoline;
static const unsigned char sg_expected[5]={0x53,0x8B,0x5C,0x24,0x0C};
static const char *sg_names[3]={"sr1_gml1_bs_walk.anim","sr1_gml1_bs_run.anim","sr1_gml1_bs_sprint.anim"};
typedef unsigned (__cdecl *sg_resolver)(unsigned,unsigned,unsigned);

static int sg_loaded(unsigned file)
{
    return file<*(unsigned *)0x024E1864 && file<5600u &&
        *(unsigned *)(0x024F2F00+file*32+0x1C)!=0;
}
static int sg_identity_valid(unsigned human,unsigned actor,unsigned owner,unsigned identity)
{
    /* Validate stable globals and the complete actor handle before touching
     * the saved human. Protects the frame before Lua notices a level reload. */
    return *(unsigned char *)0x00E94D3E==1 && human && *(unsigned *)0x021703D4==human &&
        *(unsigned *)(0x02149C64+(actor&0xFFF)*16)==human &&
        *(unsigned *)(human+0x44)==actor && *(unsigned *)(human+0x4C)==1 &&
        *(unsigned *)(human+0x5E0)==owner && owner && *(unsigned *)owner==identity && identity<0x80000000;
}
static int sg_on_foot(unsigned human)
{
    unsigned vehicle=*(unsigned *)(human+0xD74);
    return vehicle==0 || vehicle==0xFFFFFFFF;
}
static unsigned __cdecl sg_resolve(unsigned owner,unsigned key,unsigned strict)
{
    unsigned original=((sg_resolver)sg_trampoline)(owner,key,strict),i;
    if (!sg.enabled || owner!=sg.owner || !sg_identity_valid(sg_human,sg_actor,owner,sg.identity) ||
        !sg_on_foot(sg_human) || *(unsigned *)(sg_human+0x18D4)!=0 || *(unsigned char *)0x02528B48==1) return original;
    if(*(unsigned *)(sg_human+0x1138)!=sg.keys[0]) { sg.enabled=0;return original; }
    for(i=0;i<3;++i) if(!sg_loaded(sg.files[i])) { sg.enabled=0;return original; }
    return sg_route(&sg,owner,*(unsigned *)owner,key,original,(sg_definition *)0x015B8800,
        (unsigned *)0x02527D6C,(const unsigned *)sg_names);
}
static int sg_write(const void *bytes)
{
    DWORD old,ignored;
    if(!VirtualProtect((void *)0x006EF620,5,PAGE_EXECUTE_READWRITE,&old))return 0;
    memcpy((void *)0x006EF620,bytes,5);
    FlushInstructionCache(GetCurrentProcess(),(void *)0x006EF620,5);
    VirtualProtect((void *)0x006EF620,5,old,&ignored);return 1;
}
static int sg_install(void)
{
    unsigned char *tr;
    if(sg_installed)return !memcmp((void *)0x006EF620,sg_patch,5);
    /* Validate the allocator capacity/increment routine too, even though the
     * core performs its exact bounded operation without a nested native call. */
    static const unsigned char alloc_expected[]={0x8B,0x0D,0x6C,0x7D,0x52,0x02,0x81,0xF9,0x7C,0x15,0,0};
    if(memcmp((void *)0x006EF620,sg_expected,5) || memcmp((void *)0x006E9040,alloc_expected,sizeof alloc_expected))return 0;
    tr=(unsigned char *)VirtualAlloc(0,10,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
    if(!tr)return 0;
    memcpy(tr,sg_expected,5);tr[5]=0xE9;*(int *)(tr+6)=(int)(0x006EF625-(unsigned)(tr+10));
    FlushInstructionCache(GetCurrentProcess(),tr,10);sg_trampoline=tr;
    sg_patch[0]=0xE9;*(int *)(sg_patch+1)=(int)((unsigned)sg_resolve-0x006EF625);
    if(!sg_write(sg_patch)) { VirtualFree(tr,0,MEM_RELEASE);sg_trampoline=0;return 0; }
    sg_installed=1;return 1;
}
static void sg_shutdown(void)
{
    sg.enabled=0;
    if(sg_installed && !memcmp((void *)0x006EF620,sg_patch,5) && sg_write(sg_expected)) {
        sg_installed=0;
        /* Cloned definitions and their name pointers remain in the engine's
         * process-lifetime pool. Host DLL itself must remain loaded until the
         * game exits; ordinary toggle-off does not unload it. */
    }
}
#ifndef SR1_GAIT_NO_LUA
static int l_sr1_gait(lua_State *L)
{
    unsigned owner,identity,human,actor,keys[3],files[3],i,source[3],before;
    sg_state prior;
    if(lua_type(L,1)==LUA_TSTRING && !strcmp(lua_tostring(L,1),"status")) {
        lua_pushboolean(L,sg.enabled!=0);lua_pushinteger(L,sg.used);return 2;
    }
    if(!lua_toboolean(L,1)) { sg.enabled=0;lua_pushboolean(L,1);return 1; }
    human=(unsigned)luaL_checkinteger(L,2);owner=(unsigned)luaL_checkinteger(L,3);
    actor=(unsigned)luaL_checkinteger(L,4);identity=(unsigned)luaL_checkinteger(L,5);
    for(i=0;i<3;++i){keys[i]=(unsigned)luaL_checkinteger(L,6+i);files[i]=(unsigned)luaL_checkinteger(L,9+i);}
    const char *why="";
    char whybuf[96];
    if(!sg_identity_valid(human,actor,owner,identity)){why="player identity changed";goto fail;}
    if(!sg_on_foot(human)){why="not on foot";goto fail;}
    if(*(unsigned *)(human+0x18D4)){why="in a vehicle";goto fail;}
    if(*(unsigned char *)0x02528B48==1){why="multiplayer";goto fail;}
    for(i=0;i<3;++i)if(keys[i]==0xFFFFFFFF || keys[i]>=0x2A4 || !sg_loaded(files[i])){
        _snprintf_s(whybuf,sizeof whybuf,_TRUNCATE,"state %u key %08X file %08X not usable",i,keys[i],files[i]);why=whybuf;goto fail;}
    if(*(unsigned *)(human+0x1138)!=keys[0]){why="walk state changed";goto fail;}
    if(!sg_install()){why="resolver hook not installed (code at 0x006EF620 differs)";goto fail;}
    for(i=0;i<3;++i){ source[i]=((sg_resolver)sg_trampoline)(owner,keys[i],0);
        if(source[i]>=*(unsigned *)0x02527D6C){
            _snprintf_s(whybuf,sizeof whybuf,_TRUNCATE,"no native definition for state %u (key %08X -> %08X)",i,keys[i],source[i]);why=whybuf;goto fail;} }
    before=*(unsigned *)0x02527D6C;
    if(before>SG_CAPACITY-3 || sg.used>SG_CACHE-3){why="definition pool full";goto fail;}
    prior=sg;
    sg.enabled=1;sg.owner=owner;sg.identity=identity;
    for(i=0;i<3;++i){sg.keys[i]=keys[i];sg.files[i]=files[i];}
    for(i=0;i<3;++i)if(sg_route(&sg,owner,identity,keys[i],source[i],(sg_definition *)0x015B8800,
        (unsigned *)0x02527D6C,(const unsigned *)sg_names)==source[i]) {
        /* No intervening native calls or actor work: newly allocated unused
         * tail slots may be rolled back as one game-thread transaction. */
        memset((void *)(0x015B8800+before*0x54),0,(*(unsigned *)0x02527D6C-before)*0x54);
        *(unsigned *)0x02527D6C=before;sg=prior;sg.enabled=0;why="couldn't route the definitions";goto fail;
    }
    sg_human=human;sg_actor=actor;lua_pushboolean(L,1);return 1;
fail:
    sg.enabled=0;lua_pushboolean(L,0);
    lua_pushfstring(L,"SR1 movement could not acquire verified native gait definitions: %s",why);return 2;
}
#endif
#endif
