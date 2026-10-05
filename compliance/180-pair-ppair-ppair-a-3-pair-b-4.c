/* 180: CHECK(&pair == ppair && ppair->a == 3 && pair.b == 4);
 *
 * monolithic.c:9927 (expressions)
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
    int a = 7, b = 2, c = -7;
    struct c99_pair pair = {3, 4};
    struct c99_pair *ppair = &pair;
    CHECK(+a == 7 && -a == -7 && (!a) == 0 && (!!a) == 1);
    CHECK(~0 == -1 && ~a == -8);
    CHECK(&pair == ppair && ppair->a == 3 && pair.b == 4);
    return 0;
}
