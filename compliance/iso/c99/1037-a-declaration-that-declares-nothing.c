/* 1037: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7p2: a declaration shall declare at least a
 * declarator, a tag, or the members of an enumeration.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

typedef int;

int main(void)
{
    return 0;
}
