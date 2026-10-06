/* 1064: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.10.1: the conditional-inclusion directives are a
 * grammar, so each #endif and #elif shall close an open #if.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

#if 1
int main(void)
{
    return 0;
}
