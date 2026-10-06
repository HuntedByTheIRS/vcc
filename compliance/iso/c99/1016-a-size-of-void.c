/* 1016: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.3.4p1: the sizeof operator shall not be applied to
 * an expression that has function type or an incomplete type, to the
 * parenthesized name of such a type, or to an expression that designates a
 * bit-field member.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    return (int)sizeof(void);
}
