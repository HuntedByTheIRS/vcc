/* 1061: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.10.3.2p1: each # preprocessing token in the
 * replacement list for a function-like macro shall be followed by a
 * parameter as the next preprocessing token in the replacement list.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

#define X(a) # 1

int main(void)
{
    return X(2);
}
