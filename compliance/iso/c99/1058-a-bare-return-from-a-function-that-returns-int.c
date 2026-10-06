/* 1058: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.6.4p1: a return statement without an expression
 * shall only appear in a function whose return type is void.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int f(void)
{
    return;
}

int main(void)
{
    return 0;
}
