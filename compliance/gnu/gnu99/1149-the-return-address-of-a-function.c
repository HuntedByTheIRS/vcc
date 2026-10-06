/* 1149: the-return-address-of-a-function
 *
 * GCC 7.6 Getting the Return or Frame Address of a Function: "Built-in
 * Function: void * __builtin_return_address (unsigned int level) This function
 * returns the return address of the current function, or of one of its callers.
 * A value of 0 yields the return address of the current function."
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
    void *caller = __builtin_return_address(0);

    CHECK(caller != NULL);
    return 0;
}
