/* 0280: CHECK(made.a == 11 && made.b == 22);
 *
 * monolithic.c:10406 (functions)
 */

#include <stdio.h>

typedef struct c99_pair { int a, b; } c99_pair_t;

static c99_pair_t c99_make_pair(int a, int b)
{
    c99_pair_t result;
    result.a = a;
    result.b = b;
    return result;
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    c99_pair_t made;
    made = c99_make_pair(11, 22);
    CHECK(made.a == 11 && made.b == 22);
    return 0;
}
