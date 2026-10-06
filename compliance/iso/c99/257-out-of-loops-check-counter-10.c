/* 257: out_of_loops: CHECK(counter == 10);
 *
 * monolithic.c:10199 (control-flow)
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
    {
    int counter = 0;
    goto forward;
    backward_target:
            ++counter;
    if (counter < 3) goto backward_target;
    forward:
            counter = 10;
    out_of_loops:
            CHECK(counter == 10);
    }
    return 0;
}
