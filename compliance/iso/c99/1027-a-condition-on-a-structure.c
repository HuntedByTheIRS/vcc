/* 1027: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.15p2: the first operand shall have scalar type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a; };

int main(void)
{
    struct S s = {1};
    return s ? 1 : 2;
}
