/* 0385: CHECK((void *)0 == (int *)0);
 *
 * monolithic.c:10819 (pointers)
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
    CHECK((void *)0 == (int *)0);
    }
    return 0;
}
