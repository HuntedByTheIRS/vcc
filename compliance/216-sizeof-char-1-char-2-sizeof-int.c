/* 216: CHECK(sizeof((char)1 + (char)2) == sizeof(int));
 *
 * monolithic.c:9982 (expressions)
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
    CHECK(sizeof((char)1 + (char)2) == sizeof(int));
    return 0;
}
