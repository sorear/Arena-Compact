#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*
 * This module requires two things that aren't quite ANSI-implementable,
 * but can be done on all normal computers with a bit of undefined
 * behavior.  If your computer is not normal (if (char*)(i+1) !=
 * ((char*)i)+1, or if "properly aligned" does not refer being a multiple
 * of some power of two in char-difference representation), you will need to
 * read and tweak the following.
 */

/*
 * We need pages, which are fairly large objects with the property that
 * a pointer to any interior char can be mapped to a pointer to the whole.
 * Pages must have at least as much alignment as any other used type, and
 * it must be possible to page-align an arbitrary pointer.
 */
#define BIBOP_PAGE_SIZE 4096
#define PAGE2START(p) INT2PTR(char *, (PTR2UV(p) & ~4095))

/*
 * We also need the ability to do struct-ish layout at runtime.  This
 * is actually portable, if we know how many alignment bytes to generate.
 */
#define DECLASTRUCT_(t) struct bibop_alignify_##t { char x; t val; };
#define ALIGNOF_(ty) (IV)((char*)(&((struct bibop_alignify_##ty *)0)->val)- \
    (char*)0)

typedef SV *SVREF;

DECLASTRUCT_(NV)
DECLASTRUCT_(SVREF)
DECLASTRUCT_(IV)
DECLASTRUCT_(char)
DECLASTRUCT_(U16)
DECLASTRUCT_(U32)

#define PAD(ofs, ty) ((ofs + ALIGNOF_(ty) - 1) & ~ALIGNOF_(ty))

/* first keys, then formats, then pages, then fields, then objects */

/* no keys needed yet - without types they can just be scalars */

struct format_field {
    SV *key;
    int offset;
};

static void
field_get(SV *out, void *body, struct format_field *ff)
{
    SV *ourscalar = *(INT2PTR(SV **, PTR2UV(body) + ff->offset));

    SvSetSV(out, ourscalar);
}

static void
field_put(void *body, struct format_field *ff, SV *in)
{
    SV *ourscalar = *(INT2PTR(SV **, PTR2UV(body) + ff->offset));

    SvSetSV(ourscalar, in);
}

static void
field_init(void *body, struct format_field *ff, SV *in)
{
    SV **ourscalar = INT2PTR(SV **, PTR2UV(body) + ff->offset);

    *ourscalar = newSVsv(in);
}

static void
field_release(void *body, struct format_field *ff)
{
    SV *ourscalar = *(INT2PTR(SV **, PTR2UV(body) + ff->offset));

    SvREFCNT_dec(ourscalar);
}

/**/

#define BIBOP_PAGE_SIZE 4096
#define BIBOP_ALLOC_GRAN 255

struct format_data;

struct free_header {
    struct free_header *next;
};

struct page_header {
    struct format_data *format;
    struct page_header *link;
};

static struct page_header *free_pages;

struct format_data
{
    struct page_header *first_page;
    struct free_header *free_list;

    int order; /* log2 of field count */
    int bytes; /* bytes per object */

    SV *format_sv;

    struct format_field fields[1];
};

struct format_data *null_format;

static struct format_field *
lookup_field(struct format_data *format, SV *field)
{
    struct format_field *fp = &format->fields[0];
    int shift = 1 << format->order;

    for (; shift; shift >>= 1)
        if (field >= fp[shift].key)
            fp += shift;

    if (fp->key == field)
        return fp;
    else
        return 0;
}

static void *
format_getbody(struct format_data *format)
{
    struct free_header *body = format->free_list;
    UV wraddr;
    int i, end_page;

    if (body) {
        format->free_list = body->next;
        return (void*)body;
    }

    if (!free_pages) {
        struct page_header *block;

        Newxc(block, (BIBOP_ALLOC_GRAN + 1) * BIBOP_PAGE_SIZE -
            MEM_ALIGNBYTES, char, struct page_header);

        block = INT2PTR(struct page_header *,
            (PTR2UV(block) + BIBOP_PAGE_SIZE - 1) & ~BIBOP_PAGE_SIZE);

        for (i = 0; i < BIBOP_ALLOC_GRAN; i++) {
            block[i].link = free_pages;
            free_pages = &block[i];
        }
    }

    wraddr = PTR2UV(free_pages) + sizeof(struct page_header);
    free_pages = free_pages->link;

    end_page = wraddr + ((BIBOP_PAGE_SIZE - sizeof(struct page_header)) /
        format->bytes) * format->bytes;

    for (; wraddr < end_page; wraddr += format->bytes) {
        struct free_header *object = INT2PTR(struct free_header*, wraddr);

        object->next = format->free_list;
        format->free_list = object;
    }

    return format_getbody(format);
}

static void
format_putbody(struct format_data *format, void *body)
{
    struct free_header *frh = (struct free_header *)body;

    frh->next = format->free_list;
    format->free_list = frh;
}

static void
format_releaseall(struct format_data *form, void *body);

static struct format_data *
format_ofbody(void *body);

static struct format_data *
format_add(struct format_data *base, SV *field);

static struct format_data *
format_del(struct format_data *base, SV *field);

/**/

static HV *objh_stash;

static int
objh_destroy(pTHX_ SV *objh, MAGIC *mg)
{
    void *body = mg->mg_ptr;
    struct format_data *format = format_ofbody(body);

    format_releaseall(format, body);
    format_putbody(format, body);
}

static MGVTBL objh_magicness = { 0, 0, 0, 0, objh_destroy };

static void
obj_dehandle(SV *objh, struct format_data **form, void **body)
{
    MAGIC *mgp;
    SV *hobj;

    SvGMAGIC(objh);

    if (!SvROK(objh))
        croak("handle must be passed by reference");

    hobj = SvRV(objh);

    if (SvMAGICAL(hobj)) {
        for (mgp = SvMAGIC(hobj); mgp; mgp = mgp->mg_moremagic) {
            if (mgp->mg_virtual == &objh_magicness) {
                goto foundit; /* want next STEP; */
            }
        }
    }

    croak("handle has incorrect magic");

foundit:
    *body = (void*) mgp->mg_ptr;
    *form = format_ofbody(*body);
}

static void
obj_relocate(SV *objh, void *body2)
{
    /* no need to muck with hashing, yet */
    /* also, objh has already been validated */
    SV *hobj = SvRV(objh);
    MAGIC *mgp;

    for (mgp = SvMAGIC(hobj); mgp; mgp = mgp->mg_moremagic) {
        if (mgp->mg_virtual == &objh_magicness) {
            break;
        }
    }

    mgp->mg_ptr = (char*) body2;
}

/* creates a reference */
static SV *
objh_new_empty()
{
    void *body = format_getbody(null_format);
    SV *self = newSV(0);
    SV *ref = newRV_noinc(self);

    MAGIC *mg = sv_magicext(self, 0, PERL_MAGIC_ext, &objh_magicness, body, 0);

    sv_bless(ref, objh_stash);

    return ref;
}

static void
obj_read(SV *out, SV *objh, SV *field)
{
    struct format_data *format;
    struct format_field *ff;
    void *body;

    obj_dehandle(objh, &format, &body);

    ff = lookup_field(format, field);

    if (ff) {
        field_get(out, body, ff);
        return;
    }

    /* no conversions yet - no types! */

    croak("field not found");
}

static void
obj_write(SV *obj, SV *field, SV *in)
{
    struct format_data *format;
    struct format_field *ff;
    void *body;
    struct format_data *form2;
    void *body2;

    obj_dehandle(obj, &format, &body);
    ff = lookup_field(format, field);

    if (ff) {
        field_set(body, ff, in);
        return;
    }

    /* no types, so no need to check for other typeds */

    form2 = format_add(format, field);
    body2 = format_getbody(form2);
    reformat(body, format, body2, form2);

    field_init(body2, lookup_field(form2, field), in);

    obj_relocate(obj, body2);
    format_putbody(format, body);
}

static int
obj_exists(SV *objh, SV *field)
{
    struct format_data *format;
    void *body;

    obj_dehandle(objh, &format, &body);
    return lookup_field(format, field) ? 1 : 0;
}

static void
obj_delete(SV *obj, SV *field)
{
    struct format_data *format;
    void *body;
    struct format_data *form2;
    void *body2;

    obj_dehandle(obj, &format, &body);

    if (!lookup_field(format, field))
        croak("no such field");

    form2 = format_del(format, field);
    body2 = format_getbody(form2);
    reformat(body, format, body2, form2);

    field_release(body, lookup_field(format, field));

    obj_relocate(obj, body2);
    format_putbody(format, body);
}

#if 0
static HV *key_cache;
static HV *stash_BIBOP_Key;

static SV *
find_key(SV *name, SV *type, Boolean create, Boolean *created)
{
    HE *khe = hv_fetch_ent(key_cache, name, create, 0);

    if (!khe) {
        if (create)
            croak("key memo corruption: failed to extend hash (tied?)");
        return 0;
    }

    SV *ref = HeVAL(khe);

    if (SvROK(ref)) {
        SV *key = SvRV(ref);

        if (SvREADONLY(key) && SvOBJECT(key) &&
                SvSTASH(key) == stash_BIBOP_Key) {
            return key;
        }
    }

    if (SvOK(ref))
        croak("key memo corruption: non-keyref in table");


    SV *ref = 
                croak("key memo corruption: not a valid key");
            }
        } else if (!SvOK(ref)) {
            if (!create) {
                


        return 0;



    if (!SvOK(HeVAL(khe))) {
        if (!create)
            croak("key memo table corruption - value of undef");

        s
        *created = 1;
        if (SvOK(HeVAL(khe)) || )
            return HeVAL(khe);

        *created = 1;

    if (khe && !create)
        return khe;

    d

/*
 * This doesn't actually have to correspond to the system page size.
 * Which is a good thing, because you can't find that out portably.
 */

struct format_field
{
    size_t byte_offset;


#endif
