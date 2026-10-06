/* 1148: object-size-checking-with-builtin-object-size
 *
 * GCC 7.10 Object Size Checking: "Built-in Function: size_t
 * __builtin_object_size (const void * ptr, int type) This built-in construct
 * returns a constant number of bytes from ptr to the end of the object ptr
 * pointer points to (if known at compile time)."
 *
 * unimplemented: __builtin_object_size.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char buf[32];

    CHECK(__builtin_object_size(buf, 0) == 32);
    CHECK(__builtin_object_size("hello", 0) == 6);
    return 0;
}
