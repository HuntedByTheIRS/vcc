/* 0084: CHECK(c99_const_object == 7);
 *
 * monolithic.c:9653 (declarations)
 */

#include <stdio.h>

static const int c99_const_object = 7;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_const_object == 7);
    return 0;
}
