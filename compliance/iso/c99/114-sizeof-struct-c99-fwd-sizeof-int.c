/* 114: CHECK(sizeof(struct c99_fwd) == sizeof(int));
 *
 * monolithic.c:9726 (declarations)
 */

#include <stdio.h>

struct c99_fwd;

static struct c99_fwd *c99_fwd_ptr;

struct c99_fwd { int member; };

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    struct c99_fwd fwd = {5};
    CHECK(fwd.member == 5);
    c99_fwd_ptr = &fwd;
    CHECK(c99_fwd_ptr->member == 5);
    CHECK(sizeof(struct c99_fwd) == sizeof(int));
    return 0;
}
