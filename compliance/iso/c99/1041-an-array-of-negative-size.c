/* 1041: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7.5.2p1: if the expression between the brackets is a
 * constant expression, it shall have a value greater than zero.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int a[-1];

int main(void)
{
    return 0;
}
