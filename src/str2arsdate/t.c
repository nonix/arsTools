#include <stdio.h>
#include "liblah.h"
/*
gcc t.c -L. -llahlib -o t
*/
void main(int argc, char* argv[]) {
    int ret = 0;
    str2arsdate(argv[1],1,&ret);
    printf("%ld\n", ret);
}