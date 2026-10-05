/* 913: CHECK((??- mask) == ~0x05);
 *
 * monolithic.c:12135 (trigraphs)
 * requires-define: C99_TRIGRAPHS
 * trigraphs are gone from the standard this compiler is built
 * for, gcc needs -trigraphs, and this compiler reports them unsupported
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int mask = 0x05;
    CHECK((??- mask) == ~0x05);
    return 0;
}
