/* 0102: CHECK(LOCAL_A + LOCAL_B + LOCAL_C == 18);
 *
 * monolithic.c:9691 (declarations)
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
    enum c99_local_enum { LOCAL_A = 5, LOCAL_B, LOCAL_C };
    CHECK(LOCAL_A + LOCAL_B + LOCAL_C == 18);
    }
    return 0;
}
