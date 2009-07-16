#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

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
#define PAGE_LOG2 12
#define PAGE2START(p) INT2PTR(char *, (PTR2UV(p) & ~4095))
#define PAGESKIP(p) ((0 - PTR2UV(p)) & 4095)

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

#define DEBUG(x) x

/**** generic perly stuff ****/
static MAGIC *
magicref_by_vtbl(SV *objh, MGVTBL *v, const char *name)
{
    MAGIC *mgp;

    SvGETMAGIC(objh);

    if (!SvROK(objh))
        croak("%s must be a reference", name);

    objh = SvRV(objh);

    if (SvMAGICAL(objh))
        for (mgp = SvMAGIC(objh); mgp; mgp = mgp->mg_moremagic)
            if (mgp->mg_virtual == v)
                return mgp;

    croak("%s has incorrect magic", name);
}

static SV *
makemagicref(MGVTBL *v, HV *stash, SV *obp, char *chp, U32 size)
{
    SV *self = newSV(0);
    SV *sref = newRV(self);
    SAVEFREESV(sref);
    SAVEFREESV(self);

    sv_magic(self, obp, PERL_MAGIC_ext, chp, size);
    SvMAGIC(self)->mg_virtual = v;

    sv_bless(sref, stash);

    return sref;
}
/* no keys needed yet - without types they can just be scalars */

struct format_field {
    SV *key;
    int offset;
};

static void
field_get(SV *out, char *body, struct format_field *ff)
{
    SV *ourscalar = *(SV **)(body + ff->offset);

    SvSetSV(out, ourscalar);
}

static void
field_put(char *body, struct format_field *ff, SV *in)
{
    SV *ourscalar = *(SV **)(body + ff->offset);

    SvSetSV(ourscalar, in);
}

static void
field_init(char *body, struct format_field *ff, SV *in)
{
    SV **ourscalar = (SV **)(body + ff->offset);

    *ourscalar = newSVsv(in);
}

static void
field_release(char *body, struct format_field *ff)
{
    SV *ourscalar = *(SV **)(body + ff->offset);

    SvREFCNT_dec(ourscalar);
}

static void
field_copy(char *body1, int offset1, char *body2, int offset2)
{
    *(SV**)(body2+offset2) = *(SV**)(body1+offset1);
}

/**/

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
    size_t bytes; /* bytes per object */
    int count; /* of fields */
    int chaff; /* initial padding */

    SV *sv;

    struct format_field fields[1];
};

struct format_data *null_format;
static HV *format_cache;
static HV *format_stash;

static int
format_destroy(pTHX_ SV *formobj, MAGIC *mg)
{
    struct format_data *f = (struct format_data *)mg->mg_ptr;
    DEBUG(warn("DESTROYing format at %x\n", (int)f));

    SV **key;
    int klen;
    HE *he;

    /* since each object holds a reference to the format, all of our
       pages must be empty */
    struct page_header *p = f->first_page;
    int i;

    while (p) {
        struct page_header *p2 = p->link;
        p->link = free_pages;
        free_pages = p;
        p = p2;
    }

    klen = ((1 << f->order) - f->chaff);
    Newx(key, klen, SV *);

    for (i = f->chaff; i < (1 << f->order); i++) {
        SvREFCNT_dec(f->fields[i].key);
        key[i - f->chaff] = f->fields[i].key;
    }

    hv_delete(format_cache, (char*)key, klen*sizeof(SV), G_DISCARD);

    Safefree(f);

    return 0;
}

static MGVTBL format_magic = { 0, 0, 0, 0, format_destroy };

static struct format_field *
lookup_field(struct format_data *format, SV *field)
{
    struct format_field *fp = &format->fields[0];
    int shift = 1 << format->order;
    shift >>= 1;

    for (; shift; shift >>= 1)
        if (field >= fp[shift].key)
            fp += shift;

    if (fp->key == field)
        return fp;
    else
        return 0;
}

static char *
format_getbody(struct format_data *format)
{
    struct free_header *body = format->free_list;
    struct page_header *page;
    UV wraddr;
    int i;
    UV end_page;

    SvREFCNT_inc(format->sv);

    if (body) {
        format->free_list = body->next;

ret:
        DEBUG(warn("allocing body at %x for %x\n", (int)body, (int)format));
        return (char*)body;
    }

    if (!free_pages) {
        char *block;
        int bytes = (BIBOP_ALLOC_GRAN + 1) * BIBOP_PAGE_SIZE - MEM_ALIGNBYTES;
        int skip;
        Newx(block, bytes, char);

        skip = PAGESKIP(block);
        block += skip;
        bytes -= skip;

        for (i = 0; i < bytes; i += BIBOP_PAGE_SIZE) {
            ((struct page_header *) &block[i])->link = free_pages;
            free_pages = (struct page_header *)&block[i];
        }
    }

    page = free_pages;
    wraddr = PTR2UV(page) + sizeof(struct page_header);
    free_pages = free_pages->link;
    page->link = format->first_page;
    page->format = format;
    format->first_page = page;

    end_page = wraddr + ((BIBOP_PAGE_SIZE - sizeof(struct page_header)) /
        format->bytes) * format->bytes;

    for (; wraddr < end_page; wraddr += format->bytes) {
        struct free_header *object = INT2PTR(struct free_header*, wraddr);

        object->next = format->free_list;
        format->free_list = object;
    }

    body = format->free_list;
    format->free_list = body->next;
    goto ret;
}

static void
format_putbody(struct format_data *format, char *body)
{
    struct free_header *frh = (struct free_header *)body;

    DEBUG(warn("freeing body at %x for %x\n", (int)body, (int)format));
    frh->next = format->free_list;
    format->free_list = frh;

    SvREFCNT_dec(format->sv);
}

static void
format_releaseall(struct format_data *frm, char *body)
{
    int i;
    for (i = frm->chaff; i < frm->chaff + frm->count; i++) {
        field_release(body, &frm->fields[i]);
    }
}

static void
reformat(char *body1, struct format_data *form1,
        char *body2, struct format_data *form2)
{
    int p1, slots1, p2, slots2;

    slots1 = 1 << form1->order;
    slots2 = 1 << form2->order;

    for (p1 = form1->chaff, p2 = form1->chaff; p1 < slots1 && p2 < slots2; ) {
        if (form1->fields[p1].key < form2->fields[p2].key)
            p1++;
        else if (form1->fields[p1].key > form2->fields[p2].key)
            p2++;
        else {
            field_copy(body1, form1->fields[p1].offset,
                body2, form2->fields[p2].offset);
            p1++; p2++;
        }
    }
}

static struct format_data *
format_ofbody(char *body)
{
    return ((struct page_header *)PAGE2START(body))->format;
}

static struct format_data *
format_build(SV **fields, int nfields)
{
    int slots, order, i, chaff;
    struct format_data *frm;

    for (order = 0, slots = 1; slots < nfields; slots <<= 1, order++);

    Newxc(frm, sizeof(struct format_data) + (slots - 1) *
        sizeof(struct format_field), char, struct format_data);

    DEBUG(warn("creating format at %x\n", (int)frm));
    chaff = frm->chaff = slots - nfields;

    for (i = 0; i < chaff; i++)
        frm->fields[i].key = 0;

    frm->bytes = 0;
    /* for now, just use consequtive addresses with no padding */
    for (i = 0; i < nfields; i++) {
        frm->fields[i + chaff].key = fields[i];
        frm->fields[i + chaff].offset = frm->bytes;
        frm->bytes += sizeof(SV*);
    }

    /* leave room for a freelist pointer */
    if (frm->bytes < sizeof(struct free_header))
        frm->bytes = sizeof(struct free_header);

    frm->order = order;
    frm->count = nfields;

    frm->free_list = 0;
    frm->first_page = 0;

    return frm;
}

static struct format_data *
format_find(SV **fields, int nfields)
{
    SV** he = hv_fetch(format_cache, (char*)fields, nfields*sizeof(SV*), 0);
    SV *fref;
    struct format_data *frm;
    int i;

    if (he) {
        frm = (struct format_data *)
            magicref_by_vtbl(*he, &format_magic, "format cache entry")->mg_ptr;

        if (frm->count != nfields)
            goto bad;

        for (i = 0; i < frm->chaff; i++)
            if (frm->fields[i].key != 0)
                goto bad;
        for (i = 0; i < nfields; i++)
            if (frm->fields[i+frm->chaff].key != fields[i])
                goto bad;

        return frm;
bad:
        croak("inconsistency in format cache");
    }

    frm = format_build(fields, nfields);

    fref = makemagicref(&format_magic, format_stash, 0, (char*)frm, 0);
    frm->sv = SvRV(fref);

    if (!hv_store(format_cache, (char*)fields, nfields*sizeof(SV*), fref, 0))
        croak("store into format cache denied?!?");
    SvREFCNT_inc(fref);
    sv_rvweaken(fref);

    return frm;
}

static struct format_data *
format_add(struct format_data *base, SV *field)
{
    SV** nfields;
    int i;

    Newx(nfields, base->count + 1, SV *);
    SAVEFREEPV(nfields);

    for (i = 0; i < base->count &&
            base->fields[i + base->chaff].key < field; i++) {
        nfields[i] = base->fields[i + base->chaff].key;
    }

    nfields[i++] = field;

    for (; i < (base->count + 1); i++) {
        nfields[i] = base->fields[i + base->chaff - 1].key;
    }

    return format_find(nfields, base->count+1);
}

static struct format_data *
format_del(struct format_data *base, SV *field)
{
    SV **nfields;
    int i, j;
    Newx(nfields, base->count - 1, SV *);
    SAVEFREEPV(nfields);

    for (i = 0, j = 0; i < base->count; i++) {
        if (base->fields[i + base->chaff].key != field)
            nfields[j++] = base->fields[i + base->chaff].key;
    }

    return format_find(nfields, base->count-1);
}

/**/

static HV *objh_stash;

static int
objh_destroy(pTHX_ SV *objh, MAGIC *mg)
{
    char *body = mg->mg_ptr;
    struct format_data *format = format_ofbody(body);

    format_releaseall(format, body);
    format_putbody(format, body);

    return 0;
}

static MGVTBL objh_magicness = { 0, 0, 0, 0, objh_destroy };

static void
obj_dehandle(SV *objh, struct format_data **frm, char **body)
{
    *body = magicref_by_vtbl(objh, &objh_magicness, "node handle")->mg_ptr;
    *frm = format_ofbody(*body);
}

static void
obj_relocate(SV *objh, char *body2)
{
    /* no need to muck with hashing, yet */
    magicref_by_vtbl(objh, &objh_magicness, "node handle")->mg_ptr = body2;
}

/* creates a reference */
static SV *
objh_new_empty()
{
    char *body = format_getbody(null_format);
    return makemagicref(&objh_magicness, objh_stash, 0, body, 0);
}

static void
obj_read(SV *out, SV *objh, SV *field)
{
    struct format_data *format;
    struct format_field *ff;
    char *body;

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
    char *body;
    struct format_data *form2;
    char *body2;

    obj_dehandle(obj, &format, &body);
    ff = lookup_field(format, field);

    if (ff) {
        field_put(body, ff, in);
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
    char *body;

    obj_dehandle(objh, &format, &body);
    return lookup_field(format, field) ? 1 : 0;
}

static void
obj_delete(SV *obj, SV *field)
{
    struct format_data *format;
    char *body;
    struct format_data *form2;
    char *body2;

    obj_dehandle(obj, &format, &body);

    if (!lookup_field(format, field))
        croak("field not found");

    form2 = format_del(format, field);
    body2 = format_getbody(form2);
    reformat(body, format, body2, form2);

    field_release(body, lookup_field(format, field));

    obj_relocate(obj, body2);
    format_putbody(format, body);
}

MODULE = Arena::BIBOP  PACKAGE = Arena::BIBOP

BOOT:
    format_cache = newHV();
    format_stash = gv_stashpv("Arena::BIBOP::Format", GV_ADD);
    null_format = format_find(NULL, 0);
    objh_stash = gv_stashpv("Arena::BIBOP::Node", GV_ADD);

PROTOTYPES: DISABLE

SV *
bnew()
    PPCODE:
        ENTER;
        ST(0) = objh_new_empty();
        SvREFCNT_inc(ST(0));
        LEAVE;
        sv_2mortal(ST(0));
        XSRETURN(1);

SV *
bget(objh, field)
        SV *objh
        SV *field
    PPCODE:
        dXSTARG;
        ENTER;
        obj_read(TARG, objh, field);
        XPUSHs(TARG);
        LEAVE;
        XSRETURN(1);

void
bput(objh, field, in)
        SV *objh
        SV *field
        SV *in
    PPCODE:
        ENTER;
        obj_write(objh, field, in);
        LEAVE;
        XSRETURN(0);

int
bexists(objh, field)
        SV *objh
        SV *field
    CODE:
        RETVAL = obj_exists(objh, field);
    OUTPUT:
        RETVAL

void
bdelete(objh, field)
        SV *objh
        SV *field
    CODE:
        ENTER;
        obj_delete(objh, field);
        LEAVE;
