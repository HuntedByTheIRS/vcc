/* 0115: CHECK(offsetof(c99_pair_t, b) == sizeof(int));
 *
 * monolithic.c:9727 (declarations)
 */

#include <stdio.h>
#include <stddef.h>

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
    CHECK(offsetof(c99_pair_t, b) == sizeof(int));
    return 0;
}
