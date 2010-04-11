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
 * This version of the storage manager identifies objects by numbers.  The top
 * 20 bits of the identifier indexes into group_table, which is used to
 * interleave identifier allocation between classes; once the classes' own
 * number is obtained, it can be used to find the correct data page.  Pages are
 * 32,768 bits in size (incidentally the same as hardware pages on x86).  This
 * is crucial in the overhead reduction strategy, as it allows us to store type
 * information once per 4KB instead of once per object, a huge savings for
 * small objects.  (Larger objects benefit from the bounding of fragmentation
 * instead.)
 *
 * In general, an integral number of objects do not fit on one page.  To avoid
 * fragmentation, we put pages into an ordered sequence, and allow objects to
 * span pages.  This means that object storage is OFTEN DISCONTIGUOUS.
 *
 * TODO: This module isn't global destruction clean either.
 *
 * TODO: Abstract the allocation logic and make it threadsafe.
 */

#define AC_PAGE_BYTES 4096

union ac_page {
    union ac_page *next;
    char payload[AC_PAGE_BYTES];
};

static union ac_page *free_page;

static void ac_push_free_page(union ac_page *pb)
{
    pb->next = free_page;
    free_page = pb;
}

static union ac_page *ac_get_free_page()
{
    union ac_page *ret;

    if (!free_page)
    {
        union ac_page *rq;
        int i;

        Newx(rq, 255, union ac_page);

        for (i = 0; i < 255; i++)
            ac_push_free_page(&rq[i]);
    }

    ret = free_page;
    free_page = ret->next;
    return free_page;
}

static void ac_delete_class(void *clp);

AC_DEFINE_HANDLE_SORT(class, 0, ac_delete_class, 0);

int ac_param_pointer_size = 32;

/* TODO Abstract the arena into an object - this, I think, will solve all the
   annoying threading questions, and give us A::SC functionality for free */

struct ac_class *ac_new_class(struct ac_type *ty, UV nbits, int lifetime,
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

    n->obj_overhead_bits =
        (lifetime == AC_LIFE_REF8) ? 8 :
        (lifetime == AC_LIFE_REF) ? 32 : 0;

    n->obj_size_bits = nbits + n->obj_overhead_bits;

    /* Leave room for the freelist pointer */
    if (n->obj_size_bits < ac_param_pointer_size)
        n->obj_size_bits = ac_param_pointer_size;

    /* Prevent object count from reaching UV_MAX */
    if (n->obj_size_bits < CHAR_BIT)
        n->obj_size_bits = CHAR_BIT;

    AC_OVERFLOW_CHECK(n->obj_size_bits, n->obj_overhead_bits);

    return n;
}

struct ac_dirent
{
    struct ac_class *cl;
    int objnum;
};

#define OBJS_PER_DIRENT 8192
#define DIRENT_SHIFT 13

/* entry 0 is an unallocated sentinel */
static struct ac_dirent *directory;
static UV dirfree = 0;

void ac_delete_class(void *clp)
{
    struct ac_class *cl = (struct ac_class *) cl;
    int ix;

    SvREFCNT_dec(cl->dtype->reflection);
    SvREFCNT_dec(cl->metaclass);
    SvREFCNT_dec((SV*)cl->stash);

    for (ix = 0; ix < cl->num_data_pages; ix++)
        ac_push_free_page(cl->data_pages[ix]);

    for (ix = 0; ix < cl->num_dirents; ix++)
    {
        directory[cl->dirents[ix]].objnum = dirfree;
        dirfree = cl->dirents[ix];
    }

    Safefree(cl->data_pages);
    Safefree(cl->dirents);
}

static void ac_push_free_obj(ac_object o) {
    struct ac_class *cl = ac_class_of(o);

    ac_object_store(o, -ac_param_pointer_size,
            ac_param_pointer_size, cl->freelist_head);
    cl->freelist_head = o;
}

static void ac_add_page(struct ac_class *cl) {
    int old_complete_objects = cl->num_data_pages * AC_PAGE_BITS /
    union ac_page *np = ac_get_free_page();
}

static void ac_destroy(ac_object o) {
    struct ac_class *cl = ac_class_of(o);

    if (cl->dtype->flags & AC_DESTROY_USED)
        cl->dtype->ops->destroy(cl->dtype, o, 0);

    ac_push_free_obj(o);

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
