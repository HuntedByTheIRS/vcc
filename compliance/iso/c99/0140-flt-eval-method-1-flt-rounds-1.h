/* 0140: CHECK(FLT_EVAL_METHOD >= -1 && FLT_ROUNDS >= -1);
 *
 * monolithic.c:9819 (types)
 */

#include <stdio.h>
#include <float.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(FLT_EVAL_METHOD >= -1 && FLT_ROUNDS >= -1);
    return 0;
}
