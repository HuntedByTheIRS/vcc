/* 1024: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.10p2: each of the operands shall have integer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a; };

int main(void)
{
    struct S s = {1};
    return s & s;
}
