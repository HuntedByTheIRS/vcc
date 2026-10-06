/* 1054: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.6.1p1: the identifier in a goto statement shall
 * name a label located somewhere in the enclosing function.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    goto nowhere;
    return 0;
}
