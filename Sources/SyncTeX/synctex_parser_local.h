/*
 VectorPDF's local configuration for the SyncTeX parser (see README.md).

 HAVE_SETLOCALE is deliberately left undefined: the parser would otherwise call setlocale(),
 which changes a process-wide setting and isn't thread-safe, every time it reads a number.
 Numbers are read with strtod_l and a C locale instead (the two strtod_l calls in
 synctex_parser.c are VectorPDF's only change to it).
 */
#ifndef VP_SYNCTEX_PARSER_LOCAL_H
#define VP_SYNCTEX_PARSER_LOCAL_H

#include <stdlib.h>
#include <xlocale.h>
#include <pthread.h>

#define HAVE_STRLCAT
#define HAVE_STRLCPY
#define SYNCTEX_INLINE inline

static locale_t _synctex_c_locale_value;
static pthread_once_t _synctex_c_locale_once = PTHREAD_ONCE_INIT;
static void _synctex_make_c_locale(void) { _synctex_c_locale_value = newlocale(LC_NUMERIC_MASK, "C", NULL); }
static inline locale_t _synctex_c_locale(void) {
    pthread_once(&_synctex_c_locale_once, _synctex_make_c_locale);
    return _synctex_c_locale_value;
}

#endif
