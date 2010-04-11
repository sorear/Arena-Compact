#include <EXTERN.h>
#include <perl.h>
#include "Compact.h"

#define HASHPTR(p,s) (((0x9E3779B9UL * PTR2UV(p)) & 0xFFFFFFFFUL) >> s)

/*
 * This file implements a system of idiotproof Perl->C handles - scalars which
 * are magically bound to C values, and cannot be tampered with from Perl code
 * by accident.  We use a hashing system to ensure that two handles are never
 * created for the same value, if enabled.
 *
 * We store the SV->C association on a magic record.  The authority for how
 * fields can be safely used is Perl_mg_free.  Currently, mg_ptr points to the
 * C-side data, and mg_obj points to the next SV in the hash chain.
 */

static int ac_free_handle_magic(pTHX_ SV *handle, MAGIC *mg);

static MAGIC *ac_find_magic(SV *scalar, ac_handle_sort *btype, const char *crk)
{
    MAGIC *mgp = SvMAGICAL(scalar) ? SvMAGIC(scalar) : NULL;

    for (; mgp; mgp = mgp->mg_moremagic)
    {
        ac_handle_sort *spec;

        if (mgp->mg_virtual->svt_free != ac_free_handle_magic)
            continue;

        spec = (ac_handle_sort *) (mgp->mg_virtual);

        if (spec->eq_class == btype->eq_class)
            return mgp;
    }

    if (crk)
        croak("%s", crk);

    return NULL;
}

static int ac_free_handle_magic(pTHX_ SV *handle, MAGIC *mg)
{
    ac_handle_sort *hs = (ac_handle_sort *)(mg->mg_virtual);

    if (hs->needcanon) {
        SV **chainp = &(hs->htab[HASHPTR(mg->ptr, hs->shift)]);

        while (*chainp) {
            if (*chainp == handle) {
                *chainp = (SV *)mg->mg_obj;
                break;
            }

            MAGIC *mgi = ac_find_magic(aTHX_ *chainp, hs,
                    "internal error: corrupted magic chain in Arena::Compact");

            chainp = (SV **) &(mgi->mg_obj);
        }
        hs->hused--;
    }

    hs->deletehandle(aTHX_ mg->ptr);

    return 0;
}

void *ac_unhandle(pTHX_ ac_handle_sort *kind, SV *val, void **cookieret,
        const char *autocroak)
{
    MAGIC *mg = ac_find_magic(aTHX_ val, kind, autocroak);

    if (mg && cookieret)
        *cookieret = ((ac_handle_sort *)(mg->mg_virtual))->cookie;

    return !mg ? NULL : mg->mg_ptr;
}

SV *ac_rehandle(pTHX_ ac_handle_sort *kind, void *val)
{
    SV *sv;
    MAGIC *mg;

    if (kind->needcanon && kind->htab) {
        /* There may already be a handle for this object. */
        SV *itr = kind->htab[HASHPTR(val, kind->shift)];

        while (itr) {
            MAGIC *mgi = ac_find_magic(aTHX_ itr, &kind->magic_type,
                    "corruption in Arena::Compact hash chain");
            if (mgi->mg_ptr == val)
                return SvREFCNT_inc(itr);
            itr = (SV *)mg->mg_obj;
        }
    }

    sv = newSV(0);
    mg = sv_magicext(sv, 0, PERL_MAGIC_ext, &kind->magic_type, 0, 0);
    mg->mg_ptr = val;

    if (kind->needcanon) {
        if (!kind->htab) {
            Newxz(kind->htab, 32, SV *);
            kind->shift = 27;
        }

        /* TODO: rehashing */

        UV hash = (UV)HASHPTR(val, kind->shift);
        mg->mg_obj = kind->htab[hash];
        kind->htab[hash] = sv;
    }

    if (kind->setuphandle)
        kind->setuphandle(sv, val);

    return sv;
}

ac_handle_sort *ac_instance_sort(ac_handle_sort *base, void *cookie, int can)
{
    ac_handle_sort *ns;
    Newx(ns, 1, ac_handle_sort);
    Copy(ns, base, 1, ac_handle_sort);

    ns->htab = NULL; /* unshare */
    ns->cookie = cookie;
    ns->needcanon = can;

    return ns;
}

void ac_free_sort(ac_handle_sort *in)
{
    Safefree(in->htab);
    Safefree(in);
}
