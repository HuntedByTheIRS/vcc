/* 070: CHECK(c99_twelve_level_pointer() == 5);
 *
 * monolithic.c:9578 (limits)
 */

#include <stdio.h>

static int c99_twelve_level_pointer(void)
{
    int value = 5;
    int *p01 = &value;
    int **p02 = &p01;
    int ***p03 = &p02;
    int ****p04 = &p03;
    int *****p05 = &p04;
    int ******p06 = &p05;
    int *******p07 = &p06;
    int ********p08 = &p07;
    int *********p09 = &p08;
    int **********p10 = &p09;
    int ***********p11 = &p10;
    int ************p12 = &p11;
    return ************p12;
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_twelve_level_pointer() == 5);
    return 0;
}
