#include <EXTEND.h>
#include <perl.h>

#include "Compact.h"

/*
 * The storage manager - the heart of Arena::Compact.  Actually, one of two
 * hearts.  This module gives Arena::Compact immunity to fragmentation, the
 * ability to return memory to the operating system, and the ability to have
 * zero per-object overhead.
 *
 * An object is regarded simply as a sequence of bits.  It is not possible to
 * have pointer access or anything like that to an object - that would be
 * premature time optimization :).  Since an object is only a sequence of bits,
 * we can do some interesting things with them.
 *
 * A single page (we currently hardcode 4K, same as hardware pages on x86, but
 * it ultimately doesn't matter) contains 4096 byets, of which we reserve 16
 * for a page header.  Given an address into a page, you can get at the page
 * header by bit manipulation of the address; this is crucial in the overhead
 * reduction strategy, as it allows us to store type information once per 4KB
 * instead of once per object, a huge savings for small objects.  (Larger
 * objects benefit from the bounding of fragmentation instead.)
 *
 * In general, an integral number of objects do not fit on one page.  To avoid
 * fragmentation, we put pages into an ordered sequence, and allow objects to
 * span pages.  This means that object storage is OFTEN DISCONTIGUOUS.
 *
 * TODO: This module isn't global destruction clean either.
 *
 * TODO: Abstract the allocation logic and make it threadsafe.
 */

#define AC_PAGE_SIZE 4096 /* NOT getpagesize() */

struct page_header
{
    struct ac_class *claz;
    struct page_header *nextp;
    struct page_header *prevp;
    UV serialno;
};

struct page_header *free_page;

static void ac_delete_class(void *clp);

AC_DEFINE_HANDLE_SORT(class, 0, ac_delete_class, 0);

struct ac_class *ac_new_class(struct ac_type *ty, UV nbytes, int lifetime,
        SV *metaclass, HV *stash)
{
    struct ac_class *n;

    Newxz(n, 1, struct ac_class);

    n->dtype = ty;
    SvREFCNT_inc(ty->reflection);
    n->reflection = ac_rehandle(&ac_hs_class, n);
    n->stash = stash;
    SvREFCNT_int((SV*)stash);
    n->metaclass = metaclass;
    SvREFCNT_inc((SV*)metaclass);
    n->lifetime = lifetime;

    n->obj_size_bytes = nbytes;

    return n;
}

void ac_delete_class(void *clp)
{
    struct ac_class *cl = (struct ac_class *) cl;
    struct page_header *ph, *nph;

    SvREFCNT_dec(cl->dtype->reflection);
    SvREFCNT_dec(cl->metaclass);
    SvREFCNT_dec((SV*)cl->stash);

    ph = (struct page_header *)cl->first;

    while (ph) {
        nph = ph->nextp;
        ph->nextp = free_page;
        free_page = ph;
        ph = nph;
    }
}

static int allocsize = 8 * AC_PAGE_SIZE;

static void more_pages(void) {
#ifdef HAS_MMAP
    struct page_header *newpages;
    int offs;
    Mmap_t mmr;

again:
    mmr = mmap(0, allocsize, PROT_READ|PROT_WRITE, MAP_ANONYMOUS|MAP_PRIVATE,
            -1, 0);

    if (mmr == MAP_FAILED && errno == EINVAL && allocsize)
    {
        /* Automatically probe large page sizes */
        allocsize <<= 1;
        goto try_again;
    }

    if (mmr == MAP_FAILED)
    {
        croak("mmap failed: %s", strerror(errno));
    }

    newpages = INT2PTR(struct page_header, mmr);

    for (offs = 0; offs < allocsize; offs += AC_PAGE_SIZE)
    {
        struct page_header *np =
            INT2PTR(struct page_header, PTR2UV(newpages) + offs);
        np->nextp = free_page;
        free_page = np;
    }
}

static void ac_refill(struct ac_class *cl) {
    if (!free_page) more_pages();
}

static void ac_destroy(ac_object o) {
    struct ac_class *cl = ac_class_of(o);

    if (cl->dtype->flags & AC_DESTROY_USED)
        cl->dtype->ops->destroy(cl->dtype, o, 0);

    ac_object_store(o, 0, sizeof(UV) * CHAR_BIT, PTR2UV(cl->freelist_head));
    cl->freelist_head = o;
    cl->used_objects--;
    SvREFCNT_dec(cl->reflection);
}

/* TODO arrange for DESTROY to be called at predictable times - ideally, only
   when the underlying object is destroyed */
static void ac_free_handle(ac_object o) {
    struct ac_class *cl = ac_class_of(o);

    if (cl->lifetime == AC_LIFE_PERL) {
        ac_destroy(o);
    } else {
        ac_unref_object(o);
    }
}

ac_object ac_new_object(struct ac_class *cl) {
    ac_object o;

    if (!cl->freelist_head)
        ac_refill(cl);

    o = cl->freelist_head;
    cl->freelist_head = INT2PTR(void, ac_object_fetch(o, 0,
                sizeof(UV) * CHAR_BIT));
    /* TODO step this down somehow, we want creating 5 billion objects to
       work */
    SvREFCNT_inc(cl->reflection);
    cl->used_objects++;

    switch (cl->lifetime)
    {
        case AC_LIFE_PERL:
            /* Do nothing; the first rehandle call will set things up. */
            /* XXX it would be nice if we could somehow avoid the hash
               table overhead for these */
            break;
        case AC_LIFE_MANUAL:
            break;
        case AC_LIFE_GC:
            break;
        case AC_LIFE_REF:
            ac_object_store(o, 0, 32, 0);
            break;
        case AC_LIFE_REF8:
            ac_object_store(o, 0, 8, 0);
            break;
        default:
            croak("unhandled lifetime");
    }

    if (cl->dtype->flags & AC_INITIALIZE_USED)
        cl->dtype->ops->initialize(cl->dtype, o, 0);

    return o;
}

void ac_ref_object(ac_object o) {
    struct ac_class *cl = ac_class_of(o);
    int old;

    switch (cl->lifetime)
    {
        case AC_LIFE_PERL:
        default:
            croak("invalid lifetime in ref_object");
        case AC_LIFE_MANUAL:
        case AC_LIFE_GC:
            return;
        case AC_LIFE_REF:
            old = ac_object_fetch(o, -AC_U32_BIT, AC_U32_BIT);
            if (old) ac_object_store(o, -AC_U32_BIT, AC_U32_BIT, old + 1);
            break;
        case AC_LIFE_REF8:
            old = ac_object_fetch(o, -AC_U8_BIT, AC_U8_BIT);
            if (old) ac_object_store(o, -AC_U8_BIT, AC_8_BIT, old + 1);
            break;
    }

    if (old == 0)
        croak("Too many references created to object");
}

void ac_unref_object(ac_object o) {
    struct ac_class *cl = ac_class_of(o);
    int new;

    switch (cl->lifetime)
    {
        case AC_LIFE_PERL:
        default:
            croak("invalid lifetime in ref_object");
        case AC_LIFE_MANUAL:
        case AC_LIFE_GC:
            return;
        case AC_LIFE_REF:
            ac_object_store(o, -AC_U32_BIT, AC_U32_BIT,
                    (new = ac_object_fetch(o, -AC_U32_BIT, AC_U32_BIT) - 1));
            break;
        case AC_LIFE_REF8:
            ac_object_store(o, -AC_U8_BIT, AC_U8_BIT,
                    (new = ac_object_fetch(o, -AC_U8_BIT, AC_U8_BIT) - 1));
            break;
    }

    if (!new)
        ac_destroy(o);
}

UV ac_object_fetch(ac_object o, UV bitoff, UV count);
IV ac_object_fetch_signed(ac_object o, UV bitoff, UV count);
void ac_object_store(ac_object o, UV bitoff, UV count, UV val);
