/* 1057: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.6.4p1: a return statement with an expression shall
 * not appear in a function whose return type is void.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

void f(void)
{
    return 1;
}

int main(void)
{
    return 0;
}
