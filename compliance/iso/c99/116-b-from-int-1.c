/* 116: CHECK(b_from_int == 1);
 *
 * monolithic.c:9793 (types)
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
    _Bool b_from_int = 42;
    CHECK(b_from_int == 1);
    return 0;
}
