/* 103: CHECK(auto_var == 3);
 *
 * monolithic.c:9699 (declarations)
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
    auto int auto_var = 3;
    CHECK(auto_var == 3);
    }
    return 0;
}
