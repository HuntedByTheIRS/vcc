/* 1000: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.2p1: the expression that denotes the called
 * function shall have type pointer to function returning void or returning
 * an object type other than an array type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int x = 1;
    return x();
}
