/* 014: CHECK(C99_TEMP_MACRO_IS_GONE == 1);
 *
 * monolithic.c:236 (preprocessor)
 */

#include <stdio.h>
#include <math.h>
#include <tgmath.h>

#define C99_TEMP_MACRO 1

#undef C99_TEMP_MACRO

#if defined(C99_TEMP_MACRO)
#error "C99_TEMP_MACRO should have been #undef'd"
#elif !defined(C99_TEMP_MACRO)
#define C99_TEMP_MACRO_IS_GONE 1
#else
#error "unreachable"
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
    CHECK(C99_TEMP_MACRO_IS_GONE == 1);
    return 0;
}
