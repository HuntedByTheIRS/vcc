/* 0022: CHECK(strcmp(func_name_probe(), "func_name_probe") == 0);
 *
 * monolithic.c:246 (preprocessor)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

#define C99_OBJ_MACRO 1999L

#define C99_STRINGIZE(x) #x

#define C99_EXPAND_AND_STRINGIZE(x) C99_STRINGIZE(x)

#define C99_SHOW_ALL(...) #__VA_ARGS__

static const char *func_name_probe(void)
{
    return __func__;
}

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
    CHECK(strcmp(C99_SHOW_ALL(1, 2, 3), "1, 2, 3") == 0);
    CHECK(strcmp(C99_SHOW_ALL(only_one), "only_one") == 0);
    CHECK(strcmp(__FILE__, "0022-strcmp-func-name-probe-func-name-probe-0.c") == 0);
    CHECK(strcmp(func_name_probe(), "func_name_probe") == 0);
    return 0;
}
