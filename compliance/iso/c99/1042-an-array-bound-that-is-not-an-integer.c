/* 1042: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7.5.2p1: the expression between the brackets shall
 * have an integer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int a[1.5];

int main(void)
{
    return 0;
}
