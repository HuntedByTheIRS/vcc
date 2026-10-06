/* 1059: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.10.1p1: the expression that controls conditional
 * inclusion shall be an integer constant expression.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

#if 1.0
#endif

int main(void)
{
    return 0;
}
