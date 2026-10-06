/* 0389: CHECK(literal[0] == 'a' && both[1] == 'b');
 *
 * monolithic.c:10835 (pointers)
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
    const char *literal = "abc";
    const char *const both = "abc";
    CHECK(literal[0] == 'a' && both[1] == 'b');
    }
    return 0;
}
