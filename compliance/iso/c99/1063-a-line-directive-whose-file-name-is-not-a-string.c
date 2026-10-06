/* 1063: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.10.4p1: the string literal of a #line directive, if
 * present, shall be a character string literal.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

#line 1 2

int main(void)
{
    return 0;
}
