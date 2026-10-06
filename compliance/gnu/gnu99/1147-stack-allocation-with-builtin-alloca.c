/* 1147: stack-allocation-with-builtin-alloca
 *
 * GCC 7.3 Builtins for Stack Allocation: "Built-in Function: void *
 * __builtin_alloca (size_t size) The __builtin_alloca function must be called at
 * block scope. The function allocates an object size bytes large on the stack of
 * the calling function. ... The lifetime of the allocated object ends just
 * before the calling function returns to its caller."
 *
 * unimplemented: __builtin_alloca.
 */

#include <stdio.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char *p = __builtin_alloca(16);

    memcpy(p, "abc", 4);
    CHECK(strcmp(p, "abc") == 0);
    return 0;
}
