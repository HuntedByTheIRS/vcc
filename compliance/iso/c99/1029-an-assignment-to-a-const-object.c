/* 1029: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.16p2: an assignment operator shall have a
 * modifiable lvalue as its left operand.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

const int x = 1;

int main(void)
{
    x = 2;
    return x;
}
