/* 164: CHECK(sa == SIG_ATOMIC_MAX && SIG_ATOMIC_MIN <= 0);
 *
 * monolithic.c:9854 (types)
 */

#include <stdio.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    sig_atomic_t sa = SIG_ATOMIC_MAX;
    CHECK(sa == SIG_ATOMIC_MAX && SIG_ATOMIC_MIN <= 0);
    return 0;
}
