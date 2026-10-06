/* 0620: CHECK(fegetround() == FE_TOWARDZERO);
 *
 * monolithic.c:11367 (numerics)
 */

#include <stdio.h>
#include <fenv.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    {
    int original = fegetround();
    CHECK(original == FE_TONEAREST || original == FE_DOWNWARD ||
                      original == FE_UPWARD || original == FE_TOWARDZERO);
    if (fesetround(FE_UPWARD) == 0) {
                    CHECK(fegetround() == FE_UPWARD);
                }
    if (fesetround(FE_TOWARDZERO) == 0) {
    CHECK(fegetround() == FE_TOWARDZERO);
            }
        }
    }
    return 0;
}
