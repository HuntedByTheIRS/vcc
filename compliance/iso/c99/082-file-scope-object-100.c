/* 082: CHECK(c99_file_scope_object == 100);
 *
 * monolithic.c:9651 (declarations)
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
    CHECK(c99_file_scope_object == 100);
    return 0;
}
