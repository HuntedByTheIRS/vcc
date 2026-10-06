/* 1066: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.10.1: the conditional-inclusion directives are a
 * grammar, so each #elif shall close an open #if and no #elif may follow an
 * #else.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

#if 1
#else
#elif 0
#endif

int main(void)
{
    return 0;
}
