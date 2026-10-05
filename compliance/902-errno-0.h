/* 902: CHECK(errno == 0);
 *
 * monolithic.c:12064 (runtime)
 */

#include <stdio.h>
#include <errno.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    errno = 0;
    CHECK(errno == 0);
    return 0;
}
