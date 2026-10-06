/* 0090: CHECK(fwd.member == 5);
 *
 * monolithic.c:9660 (declarations)
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
    return 0;
}
