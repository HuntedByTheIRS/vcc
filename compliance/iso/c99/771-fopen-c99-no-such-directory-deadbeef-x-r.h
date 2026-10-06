/* 771: CHECK(fopen("c99_no_such_directory_deadbeef/x", "r") == NULL);
 *
 * monolithic.c:11630 (stdio)
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
    CHECK(fopen("c99_no_such_directory_deadbeef/x", "r") == NULL);
    }
    return 0;
}
