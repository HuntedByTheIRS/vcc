/* 349: CHECK(pr->a == 3 && pr->b == 4);
 *
 * monolithic.c:10694 (arrays)
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
    {
    c99_pair_t *pr = &(c99_pair_t){3, 4}
    ;
    CHECK(pr->a == 3 && pr->b == 4);
    }
    return 0;
}
