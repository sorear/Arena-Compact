#ifndef ARENA_COMPACT_H
#define ARENA_COMPACT_H

/*
 * Identifies a single object.  Need not actually be a pointer, but must be
 * the size of one.
 */
typedef void *ac_object;

struct ac_type;

/*
 * Things you can do with a (sub)object of some type.  These functions are only
 * called if the corresponding bit in the type's flags word is set; this allows
 * aggregate types to pass through operations.
 */
struct ac_type_ops
{
    /*
     * Locate a subobject.  Should croak if the subobject does not exist.  If
     * the subobject is actually a Perl scalar, it can be returned instead (for
     * the perl_array and perl_hash types).
     */
    void (*subobject)(struct ac_type *ty, ac_object obj, int bit_in_obj,
            SV *name, ac_object *oret, int *bret, struct ac_type **tyret,
            SV **pret);

    /*
     * Does a subobject with the given name exist?
     */
    int (*subobject_exists)(struct ac_type *ty, ac_object obj, int bit_in_obj,
            SV *name);

    /* TODO - subobject interrogation and editing, for mutable types */

    /* Copy a value out of the (sub)object.  Croaks on non-scalar types. */
    void (*scalar_get)(struct ac_type *ty, ac_object obj, int bit_in_obj,
            SV *ret);

    /* Copy in.  Croaks if not a scalar, or data validation error. */
    void (*scalar_put)(struct ac_type *ty, ac_object obj, int bit_in_obj,
            SV *from);

    /* Bring an *uninitialized* block of memory to some zero/default state. */
    void (*initialize)(struct ac_type *ty, ac_object obj, int bit_in_obj);

    /* Drop references so an object can be deleted. */
    void (*destroy)(struct ac_type *ty, ac_object obj, int bit_in_obj);

    /*
     * Translocate an object while preserving external back references.  This
     * is called DURING the compaction process.  Only weak references should
     * need special behavior here.  The object has already been bitwise copied
     * when this is called.
     */
    void (*translocate)(struct ac_type *ty, ac_object oldo, ac_object newo,
            int bit_in_obj);

    /*
     * Generic hook for post-compaction cleanup.  Ref hash tables need to
     * rehash now.  Only called on top-level objects.
     */
    void (*postcompact)(struct ac_type *ty, ac_object obj);

    /*
     * Mark the targets of all pointers which point into GCable zones.
     */
    void (*mark)(struct ac_type *ty, ac_object obj, int bit_in_obj);

    /*
     * Run all pointers through the forwarding system, in the final phase of
     * the compaction process.
     */
    void (*forwardize)(struct ac_type *ty, ac_object obj, int bit_in_obj);

    /* Convert to a string for diagnostics */
    void (*deparse)(struct ac_type *ty, SV *strbuf);
};
