/* 1136: a-cast-to-a-union-type
 *
 * GCC 6.2.7 Cast to a Union Type: "A cast to a union type is a C extension not
 * available in C++. ... The result of a cast to a union is a temporary rvalue
 * of the union type with a member whose type matches that of the operand
 * initialized to the value of the operand."
 *
 * unimplemented: a cast to a union type.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

union value {
    int i;
    float f;
};

int main(void)
{
    union value a = (union value)42;
    union value b = (union value)1.5f;

    CHECK(a.i == 42);
    CHECK(b.f == 1.5f);
    return 0;
}
