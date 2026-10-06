/* 0298: CHECK(mixed.bytes[sizeof(int) - 1] == 1 || mixed.bytes[0] == 4);
 *
 * monolithic.c:10522 (aggregates)
 */

#include <stdio.h>

union c99_mixed {
    char c;
    short s;
    int i;
    long long ll;
    double d;
    char bytes[8];
};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    union c99_mixed mixed;
    mixed.ll = 0;
    mixed.i = 0x01020304;
    CHECK((void *)&mixed.i == (void *)&mixed);
    CHECK((void *)&mixed.c == (void *)&mixed);
    CHECK(sizeof(union c99_mixed) == 8);
    CHECK(mixed.i == 0x01020304);
    CHECK(mixed.bytes[sizeof(int) - 1] == 1 || mixed.bytes[0] == 4);
    return 0;
}
