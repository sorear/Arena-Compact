#ifndef ARENA_COMPACT_H
#define ARENA_COMPACT_H

struct ac_handle_sort
{
    MGVTBL magic_type;

    void (*setuphandle)(SV *handle, void *obj);
    void (*deletehandle)(void *obj);

    int needcanon;

    SV **htab;
    int shift;
    int hused;
};

int ac_free_handle_magic(pTHX_ SV* sv, MAGIC* mg);

#define AC_DEFINE_HANDLE_SORT(name, newfn, delfn, canon) \
    struct ac_handle_sort ac_##name = { \
        { 0, 0, 0, 0, ac_free_handle_magic, 0, 0, 0 }, \
        newfn, delfn, canon, 0, 0, 0 }

extern struct ac_handle_sort ac_hs_object, ac_hs_class, ac_hs_type;

void *ac_unhandle(struct ac_handle_sort *kind, SV *value, const char *err);

SV *ac_rehandle(struct ac_handle_sort *kind, void *inner);

/*
 * Identifies a single object.  Need not actually be a pointer; our current
 * storage manager uses them, though.  I want to implement 32 bit index
 * object IDs, though, for the sake of 64 bit platforms, eventually.
 */
typedef void *ac_object;

/*
 * A class consists of a type, some metadata controlling handles and allocation
 * behavior, and allocation bookkeeping.  All user-level objects are associated
 * with a specific class; many internal objects are associated with one of the
 * special unnamed classes for each size.
 *
 * There are no plans to support heterogenous pages; the memory savings from
 * this (~2k per class) are dwarfed by Moose metaclass overhead.
 *
 * I have an alternate design for the storage manager, where a master array
 * stores a descriptor for every 16k object IDs; this array points to a class
 * and an offset, the offset and the low bits of the object ID then index a
 * data array.  Advantages include regular treatment of large objects and
 * using 32 bit identifiers even on 64 bit systems; disadvantages include more
 * complicated allocation (the class can move...) and an extra cache line
 * fetch per object access.
 */
struct ac_type; /* forward */
struct ac_class
{
    struct ac_type *dtype;
    SV *reflection;
    SV *metaclass; /* unused, but will be kept alive as long as class exists */
    HV *stash; /* to bless handles */
    int lifetime;

    void *first_page;
    void *last_page;
    int total_objects;
    int total_pages;
    int obj_size_bytes;

    int used_objects;
    ac_object freelist_head;

    /* TODO implement compacter
    struct ac_class *nextcl;
    struct ac_class *prevcl;

    void **first_bitmap_page;
    int num_bitmap_pages;
    int bitmap_page_array_size;
    */
};

#define AC_LIFE_PERL 0
#define AC_LIFE_MANUAL 1
#define AC_LIFE_GC 2
#define AC_LIFE_REF 3
#define AC_LIFE_REF8 4

struct ac_class *ac_new_class(struct ac_type *ty, int nbytes, int lifetime,
        SV *metaclass, HV *stash);

ac_object ac_new_object(struct ac_class *cl);

void ac_ref_object(ac_object o);
void ac_unref_object(ac_object o);

/* TODO compactor
void ac_mark_object(ac_object o);

ac_object ac_forward_object(ac_object o);
*/

/* These should not be assumed to work above 32 */
UV ac_object_fetch(ac_object o, int bitoff, int count);
IV ac_object_fetch_signed(ac_object o, int bitoff, int count);
/* does no error checking, deliberately */
void ac_object_store(ac_object o, int bitoff, int count, UV val);

/*
 * Things you can do with a (sub)object of some type.  These functions fall
 * into two groups; some of them reflect user operations, and can be NULL to
 * force an unsupported-operation croak.  Others are hooks and are only called
 * if the corresponding bit in the type's flags word is set; this allows
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

    /* Copy a value out of the (sub)object. */
    void (*scalar_get)(struct ac_type *ty, ac_object obj, int bit_in_obj,
            SV *ret);

    /* Copy in.  Croaks if data validation error. */
    void (*scalar_put)(struct ac_type *ty, ac_object obj, int bit_in_obj,
            SV *from);

    /*
     * Bring an *uninitialized* block of memory to some zero/default state;
     * it will already have been zeroed.
     */
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

/*
 * Type objects are constructed in a tree to represent all data stored;
 * this is merely the base class.  Hash consing is done at the Perl level
 * (for now; it will probably need to move to XS when retyping editors go in)
 */
struct ac_type
{
    struct ac_type_ops *ops;
    unsigned int inline_size;
    unsigned int flags;
#define AC_INITIALIZE_USED 1
#define AC_DESTROY_USED 2
#define AC_TRANSLOCATE_USED 4
#define AC_POSTCOMPACT_USED 8
#define AC_MARK_USED 16
#define AC_FORWARDIZE_USED 32
    SV *reflection;
};

/*
 * Constructs an integer type (with one reference).  TODO: support bit sizes
 * over sizeof(IV)*CHAR_BIT; perhaps as a separate Math::BigInt type.
 */
struct ac_type *ac_make_int_type(int bits);

/* A floating type of defined precision. */
struct ac_type *ac_make_float_type(int expbits, int sigbits);

/* Types of the same shape as the basic Perl types. */
struct ac_type *ac_make_nv_type(void);
struct ac_type *ac_make_iv_type(void);
struct ac_type *ac_make_uv_type(void);

/* An 8-bit character in some charset. */
struct ac_type *ac_make_natl_char_type(SV *encode_instance);

struct ac_type *ac_make_ucs2_char_type(void);
struct ac_type *ac_make_ucs4_char_type(void);

/* TODO decide on string variants - expected size and references! */
struct ac_type *ac_make_string_type(void);

struct ac_type *ac_make_record_type(int nfields, const char **names,
        struct ac_type **types);

/* TODO variants by size */
struct ac_type *ac_make_hash_type(struct ac_type *kt, struct ac_type *vt);
struct ac_type *ac_make_array_type(struct ac_type *et);

/* Homogenous to save memory in large cases */
struct ac_type *ac_make_vector_type(int ct, struct ac_type *et);

/*
 * Normally, holds an internal reference (object).  Can also hold SV*, this is
 * important for transparency.  TODO: we need to distinguish these cases in
 * some way; currently reverse handles are used, but it would be better if the
 * storage manager could tell us "this is a SV"
 */
struct ac_type *ac_make_ref_type(void);

struct ac_type *ac_make_weak_ref_type(void);

/* Holds a reference to one SV */
struct ac_type *ac_make_perl_scalar_type(void);

struct ac_type *ac_make_perl_ref_type(void);
struct ac_type *ac_make_perl_weakref_type(void);

struct ac_type *ac_make_perl_array_type(void);
struct ac_type *ac_make_perl_hash_type(void);
struct ac_type *ac_make_perl_glob_type(void);
struct ac_type *ac_make_perl_filehandle_ref_type(void);

struct ac_type *ac_make_void_type(void);

/* These functions automatically handle croaking */

void ac_do_subobject(struct ac_type **typ, ac_object **op, int **offp,
        SV *selector);

void ac_do_set(struct ac_type *ty, ac_object o, int off, SV *val);
void ac_do_get(struct ac_type *ty, ac_object o, int off, SV *ret);

int ac_child_exists(struct ac_type *ty, ac_object o, int off, SV *sel);

#endif
