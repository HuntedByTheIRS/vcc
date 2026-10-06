/* 1011: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.3.2p2: the operand of the unary * operator shall
 * have pointer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int x = *1;
    return x;
}
