/* 0081: CHECK(before == 101 && after == 202L);
 *
 * monolithic.c:9650 (declarations)
 */

#include <stdio.h>

static int c99_file_scope_object = 100;

extern int c99_file_scope_object;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int before = c99_file_scope_object;
    before += 1;
    long after = before * 2L;
    CHECK(before == 101 && after == 202L);
    return 0;
}
