/* 0938: CHECK(C99_ARM == 1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#if C99_NEVER_DEFINED
#define C99_ARM 0
#else
#define C99_ARM 1
#endif

int main(void)
{
    /* An identifier that is no macro stands for zero in #if, which is what
     * makes the #else arm here the one taken. */
    CHECK(C99_ARM == 1);
#if !C99_NEVER_DEFINED
    CHECK(1);
#else
    CHECK(0);
#endif
    return 0;
}
