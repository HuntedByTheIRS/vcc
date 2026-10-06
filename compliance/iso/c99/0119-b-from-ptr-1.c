/* 0119: CHECK(b_from_ptr == 1);
 *
 * monolithic.c:9796 (types)
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
    int target_for_bool = 1;
    int *ptr_for_bool = &target_for_bool;
    _Bool b_from_ptr = ptr_for_bool;
    CHECK(b_from_ptr == 1);
    return 0;
}
