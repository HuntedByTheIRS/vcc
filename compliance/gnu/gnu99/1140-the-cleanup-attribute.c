/* 1140: the-cleanup-attribute
 *
 * GCC 6.4.1 Common Attributes: "The cleanup attribute runs a function when the
 * variable goes out of scope. This attribute can only be applied to auto
 * function scope variables ... The function must take one parameter, a pointer
 * to a type compatible with the variable."
 *
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int cleaned;

static void mark(int *p)
{
    cleaned = *p;
}

int main(void)
{
    cleaned = 0;
    {
        __attribute__((cleanup(mark))) int x = 7;
        (void)x;
        CHECK(cleaned == 0);
    }
    CHECK(cleaned == 7);
    return 0;
}
