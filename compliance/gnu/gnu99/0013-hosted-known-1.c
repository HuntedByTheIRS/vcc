/* 0013: CHECK(C99_HOSTED_KNOWN == 1);
 *
 * monolithic.c:235 (preprocessor)
 */

#include <stdio.h>
#include <math.h>
#include <tgmath.h>

#if defined(__STDC_HOSTED__)
#define C99_HOSTED_KNOWN 1
#else
#error "__STDC_HOSTED__ must be defined"
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
    CHECK(C99_HOSTED_KNOWN == 1);
    return 0;
}
