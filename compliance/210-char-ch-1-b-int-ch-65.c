/* 210: CHECK((char)(ch + 1) == 'B' && (int)ch == 65);
 *
 * monolithic.c:9969 (expressions)
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
    char ch = 'A';
    CHECK((char)(ch + 1) == 'B' && (int)ch == 65);
    return 0;
}
