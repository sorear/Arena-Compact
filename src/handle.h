#ifndef ARENA_COMPACT__HANDLE_H
#define ARENA_COMPACT__HANDLE_H

typedef struct ac_handle_sort
{
    MGVTBL magic_type;

    void (*setuphandle)(SV *handle, void *obj);
    void (*deletehandle)(void *obj);

    struct ac_handle_sort *eq_class;
    void  *cookie;

    int needcanon;

    SV **htab;
    int shift;
    UV hused;
} ac_handle_sort;

#if MGf_COPY
#define AC_NULL_COPY NULL,
#else
#define AC_NULL_COPY
#endif

#if MGf_DUP
#define AC_NULL_DUP NULL,
#else
#define AC_NULL_DUP
#endif

#if MGf_LOCAL
#define AC_NULL_LOCAL NULL,
#else
#define AC_NULL_LOCAL
#endif

#define AC_DEFINE_HANDLE_SORT(name, newfn, delfn) \
    struct ac_handle_sort ac_##name = { \
        { 0, 0, 0, 0, ac_free_handle_magic, AC_NULL_COPY, AC_NULL_DUP, \
          AC_NULL_LOCAL}, newfn, delfn, &ac_##name, 0, 0, 0, 0, 0 }

void *ac_unhandle(pTHX_ ac_handle_sort *bkind, SV *value, void **cookieret,
        const char *err);

SV *ac_rehandle(ac_handle_sort *kind, void *inner);

ac_handle_sort *ac_instance_sort(ac_handle_sort *basic, void *cookie,
        int canonical);

void ac_free_sort(ac_handle_sort *in);

#endif
