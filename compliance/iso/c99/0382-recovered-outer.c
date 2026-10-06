/* 0382: CHECK(recovered == &outer);
 *
 * monolithic.c:10809 (pointers)
 */

#include <stdio.h>
#include <stddef.h>

typedef struct c99_pair { int a, b; } c99_pair_t;

struct c99_outer {
    int pad;
    c99_pair_t inner;
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
    struct c99_outer outer = {0, {7, 8}};
    c99_pair_t *inner_ptr = &outer.inner;
    {
    struct c99_outer *recovered =
                (struct c99_outer *)(void *)((char *)inner_ptr -
                                             offsetof(struct c99_outer, inner));
    CHECK(recovered == &outer);
    }
    return 0;
}
