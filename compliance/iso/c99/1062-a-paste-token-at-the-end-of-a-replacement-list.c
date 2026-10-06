/* 1062: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.10.3.3p1: a ## preprocessing token shall not occur at
 * the beginning or at the end of a replacement list for either form of
 * macro definition.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

#define X 1 ##

int main(void)
{
    return X;
}
