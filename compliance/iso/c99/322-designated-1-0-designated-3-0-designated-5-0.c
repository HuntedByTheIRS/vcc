/* 322: CHECK(designated[1] == 0 && designated[3] == 0 && designated[5] == 0);
 *
 * monolithic.c:10629 (arrays)
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
    int designated[6] = {[4] = 40, [0] = 1, [2] = 20};
    CHECK(designated[0] == 1 && designated[2] == 20 && designated[4] == 40);
    CHECK(designated[1] == 0 && designated[3] == 0 && designated[5] == 0);
    return 0;
}
