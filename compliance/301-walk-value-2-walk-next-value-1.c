/* 301: CHECK(walk->value == 2 && walk->next->value == 1);
 *
 * monolithic.c:10530 (aggregates)
 */

#include <stdio.h>

struct c99_node {                    /* self-referential structure */
    int value;
    struct c99_node *next;
};

struct c99_nested {                  /* struct inside struct inside struct */
    struct {
        int x;
        int y;
    } point;
    union {
        int as_int;
        char as_bytes[sizeof(int)];
    } pun;
    struct c99_node chain[2];
};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    struct c99_nested nested = {
            {1, 2},
            {0},
            {{3, NULL}, {4, NULL}}
        };
    struct c99_nested copy;
    struct c99_node a = {1, NULL};
    struct c99_node b = {2, &a};
    struct c99_node *walk;
    CHECK(nested.point.x == 1 && nested.point.y == 2);
    CHECK(nested.chain[0].value == 3 && nested.chain[1].value == 4);
    CHECK(nested.chain[0].next == NULL && nested.chain[1].next == NULL);
    copy = nested;
    copy.point.x = 99;
    copy.chain[1].value = 44;
    CHECK(nested.point.x == 1 && copy.point.x == 99);
    CHECK(nested.chain[1].value == 4 && copy.chain[1].value == 44);
    walk = &b;
    CHECK(walk->value == 2 && walk->next->value == 1);
    return 0;
}
