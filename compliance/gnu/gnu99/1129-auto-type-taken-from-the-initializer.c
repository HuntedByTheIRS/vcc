/* 1129: auto-type-taken-from-the-initializer
 *
 * GCC 6.12.5 Referring to a Type with typeof: "In GNU C, but not GNU C++, you
 * may also declare the type of a variable as __auto_type. In that case, the
 * declaration must declare only one variable, whose declarator must just be an
 * identifier, the declaration must be initialized, and the type of the variable
 * is determined by the initializer."
 *
 * unimplemented: __auto_type.
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
    __auto_type n = 5;
    __auto_type d = 1.5;

    CHECK(n == 5);
    CHECK(d == 1.5);
    CHECK(sizeof(n) == sizeof(int));
    CHECK(sizeof(d) == sizeof(double));
    return 0;
}
