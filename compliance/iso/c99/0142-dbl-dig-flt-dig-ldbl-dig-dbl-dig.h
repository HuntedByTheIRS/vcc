/* 0142: CHECK(DBL_DIG > FLT_DIG && LDBL_DIG >= DBL_DIG);
 *
 * monolithic.c:9821 (types)
 */

#include <stdio.h>
#include <float.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(DBL_DIG > FLT_DIG && LDBL_DIG >= DBL_DIG);
    return 0;
}
