/* 066: CHECK(c99_deep_blocks() == 127);
 *
 * monolithic.c:9574 (limits)
 */

#include <stdio.h>

static int c99_deep_blocks(void)
{
    int depth = 0;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    return depth;
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
    CHECK(c99_deep_blocks() == 127);
    return 0;
}
