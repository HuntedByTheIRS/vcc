/* 000: CHECK(C99_OBJ_MACRO == 1999L);
 *
 * monolithic.c:215 (preprocessor)
 */

#include <stdio.h>

#define C99_OBJ_MACRO 1999L

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_OBJ_MACRO == 1999L);
    return 0;
}
