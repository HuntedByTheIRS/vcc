/* 154: CHECK(*(int *)as_ptr == 1234);
 *
 * monolithic.c:9842 (types)
 */

#include <stdio.h>
#include <stdint.h>

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
    int target = 1234;
    uintptr_t as_int = (uintptr_t)&target;
    void *as_ptr = (void *)as_int;
    CHECK(*(int *)as_ptr == 1234);
    }
    return 0;
}
