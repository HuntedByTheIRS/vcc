/* 0211: CHECK((unsigned char)c99_uc_roundtrip_probe(300) == 44);
 *
 * monolithic.c:9970 (expressions)
 */

#include <stdio.h>

static int c99_uc_roundtrip_probe(int value);

static int c99_uc_roundtrip_probe(int value)
{
    return value & 0xFF;
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
    CHECK((unsigned char)c99_uc_roundtrip_probe(300) == 44);
    return 0;
}
