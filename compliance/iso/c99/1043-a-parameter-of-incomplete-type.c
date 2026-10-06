/* 1043: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7.5.3p4: after adjustment, the parameters in a
 * parameter type list in a function declarator that is part of a definition
 * of that function shall not have incomplete type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S;

void f(struct S s)
{
    (void)s;
}

int main(void)
{
    return 0;
}
