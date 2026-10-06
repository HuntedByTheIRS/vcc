/* 1010: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.3.2p1: the operand of the unary & operator shall be
 * either a function designator, the result of a [] or unary * operator, or
 * an lvalue that designates an object that is not a bit-field and is not
 * declared with the register storage-class specifier.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a:3; };

int main(void)
{
    struct S s = {1};
    int *p = &s.a;
    return *p;
}
