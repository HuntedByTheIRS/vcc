/* 030: CHECK('\x41' == 65 && '\101' == 65 && '\?' == '?' && '\'' == 39);
 *
 * monolithic.c:288 (lexical)
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
    CHECK('\x41' == 65 && '\101' == 65 && '\?' == '?' && '\'' == 39);
    return 0;
}
