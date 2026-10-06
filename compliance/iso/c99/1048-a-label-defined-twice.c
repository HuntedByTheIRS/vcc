/* 1048: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.1p3: label names shall be unique within a function.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
a:
    a:
    return 0;
}
