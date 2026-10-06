/* 0015: CHECK(C99_NESTED_CONDITION == 1);
 *
 * monolithic.c:237 (preprocessor)
 */

#include <stdio.h>

#define C99_OBJ_MACRO 1999L

#if defined(C99_OBJ_MACRO) && (C99_OBJ_MACRO + 1 == 2000) && !defined(__cplusplus)
#define C99_NESTED_CONDITION 1
#endif

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_NESTED_CONDITION == 1);
    return 0;
}
