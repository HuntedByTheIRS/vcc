/* 1125: case-ranges-in-a-switch
 *
 * GCC 6.12.14 Case Ranges: "You can specify a range of consecutive values in
 * a single case label, like this: case low ... high : This has the same effect
 * as the proper number of individual case labels, one for each integer value
 * from low to high, inclusive."
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int upper = 0;
    int lower = 0;
    int other = 0;

    switch ('Q') {
    case 'A' ... 'Z': upper = 1; break;
    case 'a' ... 'z': lower = 1; break;
    default: other = 1; break;
    }
    CHECK(upper == 1);
    CHECK(lower == 0);
    CHECK(other == 0);
    return 0;
}
