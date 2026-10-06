/* 1118: wcstoimax-and-wcstoumax-read-a-wide-widest-integer
 *
 * ISO/IEC 9899:1999 7.8.2.1: the wcstoimax and wcstoumax functions convert
 * the initial portion of the wide string to intmax_t and uintmax_t.
 */

#include <inttypes.h>
#include <stddef.h>

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
    CHECK(wcstoimax(L"-5", NULL, 10) == -5);
    CHECK(wcstoumax(L"6", NULL, 10) == 6);
    return 0;
}
