/* 1005: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.3p1: the first operand of the . operator shall
 * have a qualified or unqualified structure or union type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int m; };

int main(void)
{
    int x = 1;
    return x.m;
}
