/* 892: CHECK(SIG_DFL != SIG_IGN && SIG_ERR != SIG_DFL && SIG_ERR != SIG_IGN);
 *
 * monolithic.c:12040 (runtime)
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
    return 0;
}
