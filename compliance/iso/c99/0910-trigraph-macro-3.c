/* 0910: CHECK(C99_TRIGRAPH_MACRO == 3);
 *
 * monolithic.c:12132 (trigraphs)
 * requires-define: C99_TRIGRAPHS
 * trigraphs are gone from the standard this compiler is built
 * for, gcc needs -trigraphs, and this compiler reports them unsupported
 */

#include <stdio.h>
#include <ctype.h>

static int g_fail;

static int g_section_checks;

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

#ifdef C99_TRIGRAPHS
/* ??= is #, ??( and ??) are brackets, ??< and ??> are braces, ??! is |,
 * ??' is ^, ??- is ~, and ??/ acts as a backslash (so it continues a line). */
??=define C99_TRIGRAPH_MACRO 1 ??/
    + 2

static int sec_18_trigraphs(void)
{
    int failures = g_fail;
    int values??(3??) = ??< 10, 20, 30 ??>;
    int mask = 0x05;

    sec_begin("18 trigraphs (built with -DC99_TRIGRAPHS)");

    CHECK(C99_TRIGRAPH_MACRO == 3);
    CHECK(values??(0??) == 10 ??!??! values??(2??) == 30);
    CHECK(sizeof values == 3 * sizeof(int));
    CHECK((??- mask) == ~0x05);               /* ??- is ~ */
    CHECK((mask ??' 0x03) == (0x05 ^ 0x03));   /* ??' is ^ */

    return g_fail - failures;
}
#endif /* C99_TRIGRAPHS */

#ifdef C99_TRIGRAPHS
/* ??= is #, ??( and ??) are brackets, ??< and ??> are braces, ??! is |,
 * ??' is ^, ??- is ~, and ??/ acts as a backslash (so it continues a line). */
??=define C99_TRIGRAPH_MACRO 1 ??/
    + 2

static int sec_18_trigraphs(void)
{
    int failures = g_fail;
    int values??(3??) = ??< 10, 20, 30 ??>;
    int mask = 0x05;

    sec_begin("18 trigraphs (built with -DC99_TRIGRAPHS)");

    CHECK(C99_TRIGRAPH_MACRO == 3);
    CHECK(values??(0??) == 10 ??!??! values??(2??) == 30);
    CHECK(sizeof values == 3 * sizeof(int));
    CHECK((??- mask) == ~0x05);               /* ??- is ~ */
    CHECK((mask ??' 0x03) == (0x05 ^ 0x03));   /* ??' is ^ */

    return g_fail - failures;
}
#endif /* C99_TRIGRAPHS */

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_TRIGRAPH_MACRO == 3);
    return 0;
}
