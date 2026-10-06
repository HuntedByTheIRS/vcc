/* 1142: a-vector-type-declared-with-vector-size
 *
 * GCC 7.8 Using Vector Instructions through Built-in Functions: "The first step
 * in using these extensions is to provide the necessary data types. This should
 * be done using an appropriate typedef: typedef int v4si __attribute__
 * ((vector_size (16)));"
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

typedef int v4si __attribute__((vector_size(16)));

int main(void)
{
    v4si a = { 1, 2, 3, 4 };
    v4si b = { 10, 20, 30, 40 };
    v4si c = a + b;

    CHECK(sizeof(v4si) == 16);
    CHECK(c[0] == 11);
    CHECK(c[3] == 44);
    return 0;
}
