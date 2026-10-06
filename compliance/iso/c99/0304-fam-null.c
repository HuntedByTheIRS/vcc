/* 0304: CHECK(fam != NULL);
 *
 * monolithic.c:10537 (aggregates)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

struct c99_fam {
    size_t length;
    char data[];
};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    struct c99_fam *fam;
    fam = malloc(sizeof *fam + 16);
    CHECK(fam != NULL);
    return 0;
}
