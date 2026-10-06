#include <stdio.h>

static int fib(int n) {
    if (n < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    int total = 0;
    for (int i = 0; i < 10; i++) {
        if (i % 2 == 0) {
            continue;
        }
        total += i;
    }
    printf("%d\n", total);
    int n = 0, prod = 1;
    while (n < 5) {
        prod *= ++n;
    }
    printf("%d\n", prod);
    printf("%d\n", fib(10));
    int sum = 0;
    for (int i = 1; i <= 100; i++) {
        sum += i;
    }
    printf("%d\n", sum);
    int grid[3][3];
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            grid[i][j] = i * 3 + j;
        }
    }
    printf("%d %d %d\n", grid[0][0], grid[1][1], grid[2][2]);
    return 0;
}
