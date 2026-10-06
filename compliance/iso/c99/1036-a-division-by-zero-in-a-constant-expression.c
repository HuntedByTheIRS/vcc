/* 1036: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.6p4: each constant expression shall evaluate to a
 * constant that is in the range of representable values for its type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

enum { A = 1 / 0 };

int main(void)
{
    return A;
}
