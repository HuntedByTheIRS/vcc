/* 0782: CHECK(impossible == NULL);
 *
 * monolithic.c:11728 (utilities)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
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
    size_t huge_size = (size_t)strtoumax("18446744073709551615", NULL, 10);
    CHECK(realloc(NULL, 4) != NULL);
    {
            /* realloc(ptr, 0) may return NULL or a pointer that must be freed. */
            void *shrunk_to_nothing = realloc(malloc(8), 0);
            free(shrunk_to_nothing);
        }
    {
    void *(*volatile allocate)(size_t) = malloc;
    void *impossible;
    CHECK(huge_size > (size_t)PTRDIFF_MAX);
    impossible = allocate(huge_size);
    CHECK(impossible == NULL);
    }
    return 0;
}
