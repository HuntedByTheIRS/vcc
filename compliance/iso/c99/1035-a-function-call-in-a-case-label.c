/* 1035: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.6p3: constant expressions shall not contain
 * assignment, increment, decrement, function-call, or comma operators,
 * except when they are contained within a subexpression that is not
 * evaluated.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int f(void);

int main(void)
{
    switch (1) {
    case f():
        return 1;
    }
    return 0;
}
