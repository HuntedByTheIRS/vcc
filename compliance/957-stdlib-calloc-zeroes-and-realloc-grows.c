/* 957: CHECK(grown[4] == 40);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int *block = calloc(4, sizeof(int));
    int *grown;
    int i;
    if (block == 0) { return 1; }
    for (i = 0; i < 4; i++) {
        CHECK(block[i] == 0);
    }
    for (i = 0; i < 4; i++) {
        block[i] = i * 10;
    }
    grown = realloc(block, 8 * sizeof(int));
    if (grown == 0) { return 2; }
    for (i = 0; i < 4; i++) {
        CHECK(grown[i] == i * 10);
    }
    grown[4] = 40;
    CHECK(grown[4] == 40);
    free(grown);
    return 0;
}
