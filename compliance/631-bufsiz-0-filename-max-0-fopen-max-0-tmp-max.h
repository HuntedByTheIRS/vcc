/* 631: CHECK(BUFSIZ > 0 && FILENAME_MAX > 0 && FOPEN_MAX > 0 && TMP_MAX > 0);
 *
 * monolithic.c:11436 (stdio)
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
    CHECK(BUFSIZ > 0 && FILENAME_MAX > 0 && FOPEN_MAX > 0 && TMP_MAX > 0);
    return 0;
}
