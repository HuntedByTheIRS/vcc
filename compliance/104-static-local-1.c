/* 104: CHECK(static_local == 1);
 *
 * monolithic.c:9700 (declarations)
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
    {
    static int static_local = 0;
    ++static_local;
    CHECK(static_local == 1);
    }
    return 0;
}
