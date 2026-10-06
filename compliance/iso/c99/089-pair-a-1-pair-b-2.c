/* 089: CHECK(pair.a == 1 && pair.b == 2);
 *
 * monolithic.c:9659 (declarations)
 */

#include <stdio.h>

typedef struct c99_pair { int a, b; } c99_pair_t;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    c99_pair_t pair = {1, 2};
    CHECK(pair.a == 1 && pair.b == 2);
    return 0;
}
