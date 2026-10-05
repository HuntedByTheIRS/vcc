/* 989: CHECK(found == 5);
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
    int found = 0;
    int i, j;
    for (i = 0; i < 3; i++) {
        for (j = 0; j < 3; j++) {
            if (i * 3 + j == 5) {
                found = 5;
                goto done;
            }
        }
    }
done:
    CHECK(found == 5);
    CHECK(i == 1 && j == 2);
    return 0;
}
