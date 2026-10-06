/* 1040: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7.2.1p3: the expression that specifies the width of a
 * bit-field shall be an integer constant expression with a nonnegative
 * value that does not exceed the width of an object of the type that would
 * be specified were the colon and expression omitted.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a:-1; };

int main(void)
{
    return 0;
}
