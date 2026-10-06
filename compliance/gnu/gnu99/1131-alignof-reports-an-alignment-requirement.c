/* 1131: alignof-reports-an-alignment-requirement
 *
 * GCC 6.12.9 Determining the Alignment of Functions, Types or Variables: "The
 * keyword __alignof__ determines the alignment requirement of a function,
 * object, or a type, or the minimum alignment usually required by a type. Its
 * syntax is just like sizeof ... after this declaration: struct foo { int x;
 * char y; } foo1; the value of __alignof__ (foo1.y) is 1"
 *
 * unimplemented: __alignof__.
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
    struct foo { int x; char y; } foo1;

    CHECK(__alignof__(char) == 1);
    CHECK(__alignof__(foo1.y) == 1);
    CHECK(__alignof__(struct foo) == __alignof__(int));
    CHECK(__alignof__(double) >= __alignof__(int));
    return 0;
}
