/* 0894: CHECK(raise(SIGUSR1) == 0);
 *
 * monolithic.c:12046 (runtime)
 */

#include <stdio.h>
#include <signal.h>
#include <stddef.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(SIG_DFL != SIG_IGN && SIG_ERR != SIG_DFL && SIG_ERR != SIG_IGN);
    {
    CHECK(signal(SIGUSR1, SIG_IGN) != SIG_ERR);
    CHECK(raise(SIGUSR1) == 0);
    }
    return 0;
}
