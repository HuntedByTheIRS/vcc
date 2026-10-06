/* 1135: a-structure-with-no-members
 *
 * GCC 6.2.3 Structures with No Members: "GCC permits a C structure to have no
 * members: struct empty { }; The structure has size zero."
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct empty { };

struct wrapper {
    int n;
    struct empty e;
};

int main(void)
{
    struct empty e;
    struct wrapper w;

    w.n = 3;
    (void)e;
    CHECK(sizeof(struct empty) == 0);
    CHECK(sizeof(struct wrapper) == sizeof(int));
    CHECK(w.n == 3);
    return 0;
}
