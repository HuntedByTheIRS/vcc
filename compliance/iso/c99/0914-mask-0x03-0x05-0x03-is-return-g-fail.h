/* 0914: CHECK((mask ??' 0x03) == (0x05 ^ 0x03)); /* ??' is ^ */ return g_fail - failures;
 *
 * monolithic.c:12136 (trigraphs)
 * requires-define: C99_TRIGRAPHS
 * trigraphs are gone from the standard this compiler is built
 * for, gcc needs -trigraphs, and this compiler reports them unsupported
 */

#include <stdio.h>
#include <ctype.h>

static int g_fail;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int failures = g_fail;
    int mask = 0x05;
    CHECK((??- mask) == ~0x05);
    CHECK((mask ??' 0x03) == (0x05 ^ 0x03));   /* ??' is ^ */

        return g_fail - failures;
    return 0;
}
