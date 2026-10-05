/* 773: CHECK(heap != NULL && zeroed != NULL);
 *
 * monolithic.c:11690 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
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
    int *heap = malloc(10 * sizeof *heap);
    int *zeroed = calloc(10, sizeof *zeroed);
    CHECK(heap != NULL && zeroed != NULL);
    return 0;
}
