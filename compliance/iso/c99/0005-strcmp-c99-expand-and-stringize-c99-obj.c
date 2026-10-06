/* 0005: CHECK(strcmp(C99_EXPAND_AND_STRINGIZE(C99_OBJ_MACRO), "1999L") == 0);
 *
 * monolithic.c:222 (preprocessor)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

#define C99_OBJ_MACRO 1999L

#define C99_STRINGIZE(x) #x

#define C99_EXPAND_AND_STRINGIZE(x) C99_STRINGIZE(x)

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
    CHECK(strcmp(C99_STRINGIZE(C99_OBJ_MACRO), "C99_OBJ_MACRO") == 0);
    CHECK(strcmp(C99_EXPAND_AND_STRINGIZE(C99_OBJ_MACRO), "1999L") == 0);
    return 0;
}
