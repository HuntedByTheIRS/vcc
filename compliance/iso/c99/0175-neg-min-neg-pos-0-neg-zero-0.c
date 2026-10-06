/* 0175: CHECK(NEG_MIN + NEG_POS == 0 && NEG_ZERO == 0);
 *
 * monolithic.c:9876 (types)
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
    enum c99_neg { NEG_MIN = -3, NEG_ZERO = 0, NEG_POS = 3 };
    CHECK(NEG_MIN + NEG_POS == 0 && NEG_ZERO == 0);
    }
    return 0;
}
