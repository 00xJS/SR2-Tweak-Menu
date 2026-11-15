#ifndef SR1_GAIT_CORE_H
#define SR1_GAIT_CORE_H
#include <string.h>
#define SG_CAPACITY 5500u
#define SG_CACHE 96u
typedef struct sg_definition { unsigned word[21]; } sg_definition;
typedef struct sg_clone { unsigned source, slot, file, gait; sg_definition snapshot; } sg_clone;
typedef struct sg_state {
    unsigned enabled, owner, identity, keys[3], files[3], used;
    sg_clone cache[SG_CACHE];
} sg_state;
static void sg_snapshot(sg_definition *dst,const sg_definition *src)
{
    *dst=*src;dst->word[5]&=~6u;memset(&dst->word[6],0,16);
}
/* Caller owns game-thread synchronization and native address/identity guards.
 * Pool metadata may point into immutable global native tables. Live asset
 * binding slots MUST be detached from the copied definition. */
static unsigned sg_route(sg_state *s, unsigned owner, unsigned identity,
    unsigned key, unsigned original, sg_definition *pool, unsigned *count,
    const unsigned *name_tokens)
{
    unsigned gait, i, slot;
    sg_definition snapshot;
    sg_definition *copy;
    if (!s->enabled || owner!=s->owner || identity!=s->identity || original>=*count || *count>SG_CAPACITY) return original;
    for (gait=0;gait<3 && s->keys[gait]!=key;++gait) {}
    if (gait==3) return original;
    sg_snapshot(&snapshot,&pool[original]);
    for (i=0;i<s->used;) {
        sg_clone *c=&s->cache[i];
        if(c->slot>=*count || pool[c->slot].word[0]!=name_tokens[c->gait] || pool[c->slot].word[3]!=c->file ||
            (c->source==original && memcmp(&snapshot,&c->snapshot,sizeof snapshot))) {
            s->cache[i]=s->cache[--s->used];continue;
        }
        if (c->source==original && c->gait==gait && c->file==s->files[gait] && c->slot<*count &&
            pool[c->slot].word[0]==name_tokens[gait] && pool[c->slot].word[3]==c->file) return c->slot;
        ++i;
    }
    if (s->used==SG_CACHE || *count==SG_CAPACITY) { s->enabled=0; return original; }
    slot=*count;copy=&pool[slot];*copy=pool[original];
    copy->word[0]=copy->word[1]=name_tokens[gait];
    copy->word[3]=s->files[gait];
    copy->word[5]&=~6u;
    memset(&copy->word[6],0,16);
    ++*count;
    s->cache[s->used].source=original;s->cache[s->used].slot=slot;
    s->cache[s->used].snapshot=snapshot;
    s->cache[s->used].file=s->files[gait];s->cache[s->used].gait=gait;++s->used;
    return slot;
}
#endif
