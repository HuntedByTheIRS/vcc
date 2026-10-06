/* 0990: CHECK(outer == 1 && inner == 2);
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

int main(void)
{
    int name = 1;
    int outer = name;
    int inner = 0;
    {
        int name = 2;
        inner = name;
    }
    /* The inner declaration is a different object, and the outer name is what
     * it was once the block ends. */
    CHECK(outer == 1);
    CHECK(inner == 2);
    CHECK(name == 1);
    return 0;
}
