/* 1006: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.3p2: the first operand of the -> operator shall
 * have type pointer to qualified or unqualified structure or pointer to
 * qualified or unqualified union.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int m; };

int main(void)
{
    struct S s = {1};
    return s->m;
}
