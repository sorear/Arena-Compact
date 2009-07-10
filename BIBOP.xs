#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

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

struct format_data
{
    struct page_header *first_page;
    struct free_header *free_list;

    int order; /* log2 of field count */
    int size; /* bytes per object */

    SV *format_sv;

    struct format_field fields[1];
};

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
    int i;

    if (body) {
        format->free_list = body->next;
        return (void*)body;
    }

    if (!free_pages) {
        struct page_header *block;

        Newxc(block, char, (BIBOP_ALLOC_GRAN + 1) * BIBOP_PAGE_SIZE -
            MEM_ALIGN_BYTES, struct page_header);

        block = INT2PTR(struct page_header *,
            (PTR2UV(block) + BIBOP_PAGE_SIZE - 1) & ~BIBOP_PAGE_SIZE);

        for (i = 0; i < BIBOP_ALLOC_GRAN; i++) {
            block[i]->link = free_pages;
            free_pages = &block[i];
        }
    }

    wraddr = PTR2UV(free_pages) + sizeof(struct page_header);
    free_pages = free_pages->link;

    for (i = 0; i < format->per_page; i++) {
        struct free_header *object = INT2PTR(struct free_header*, wraddr);

        object->next = format->free_list;
        format->free_list = object;

        wraddr += format->bytes;
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

/* format add/del stuff here */

/**/

static void
obj_dehandle(SV *objh, struct format_data **form, void **body)
{
    MAGIC *mgp;
    SV *hobj;

    SvGMAGIC(objh);

    if (!SvROK(objh))
        croak("handle must be passed by reference");

    SV *hobj = SvRV(objh);

    if (SvMAGICAL(hobj)) {
        for (mgp = SvMAGIC(hobj); mgp; mgp = mgp->moremagic) {
            if (mgp->mg_type == PERL_MAGIC_ext && mgp->mg_len == MAGIC_SIG1 &&
                    mgp->mg_private == MAGIC_SIG2) {
                goto foundit; /* want next STEP; */
            }
        }
    }

    croak("handle has incorrect magic");

foundit:
    *body = (void*) mgp->mg_ptr;
    *form = INT2PTR(struct format_data **,
        (PTR2UV(body) & ~(BIBOP_PAGE_SIZE-1)));
}

static void
obj_relocate(SV *objh, void *body2)
{
    /* no need to muck with hashing, yet */
    /* also, objh has already been validated */
    SV *hobj = SvRV(objh);
    MAGIC *mgp;

    for (mgp = SvMAGIC(hobj); mgp; mgp = mgp->moremagic) {
        if (mgp->mg_type == PERL_MAGIC_ext && mgp->mg_len == MAGIC_SIG1 &&
                mgp->mg_private == MAGIC_SIG2) {
            break;
        }
    }

    mgp->mg_ptr = (char*) body2;
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

    obj_dehandle(objh, &format, &body);
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

    obj_relocate(objh, body2);
    format_putbody(format, body);
}

static Boolean
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

    obj_dehandle(objh, &format, &body);

    if (!lookup_field(format, field))
        croak("no such field");

    form2 = format_del(format, field);
    body2 = format_getbody(form2);
    reformat(body, format, body2, form2);

    field_release(body, lookup_field(format, field));

    obj_relocate(objh, body2);
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
