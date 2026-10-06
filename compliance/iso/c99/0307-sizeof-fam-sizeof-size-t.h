/* 0307: CHECK(sizeof *fam == sizeof(size_t));
 *
 * monolithic.c:10543 (aggregates)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

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
    if (fam != NULL) {
    fam->length = 16;
    memcpy(fam->data, "0123456789abcdef", 16);
    CHECK(fam->length == 16);
    CHECK(fam->data[0] == '0' && fam->data[15] == 'f');
    CHECK(sizeof *fam == sizeof(size_t));
    }
    return 0;
}
