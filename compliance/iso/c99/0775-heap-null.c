/* 0775: CHECK(heap != NULL);
 *
 * monolithic.c:11697 (utilities)
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
    if (heap != NULL) {
    for (int i = 0; i < 10; ++i) {
                heap[i] = i * i;
            }
    CHECK(heap[9] == 81);
    heap = realloc(heap, 20 * sizeof *heap);
    CHECK(heap != NULL);
    }
    return 0;
}
