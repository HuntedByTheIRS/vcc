/* 1038: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7p4: all declarations in the same scope that refer to
 * the same object or function shall specify compatible types.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int x;
double x;

int main(void)
{
    return 0;
}
