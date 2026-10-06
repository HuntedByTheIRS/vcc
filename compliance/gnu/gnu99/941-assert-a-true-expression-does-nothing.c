/* 941: CHECK(assert_holds == 1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <assert.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int x = 3;
    int assert_holds = 1;
    assert(1);
    assert(x == 3);
    assert(x + 1 > 3);
    CHECK(assert_holds == 1);
    return 0;
}
