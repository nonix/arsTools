#include <string.h>
#include <stdlib.h>
#include <time.h>

/*

gcc -fPIC -fvisibility=hidden -shared liblah.c -o liblah.so

*/

#ifndef LIBLAH_H
#define LIBLAH_H

__attribute__((visibility("default")))

void str2arsdate(const char* ymd, const int* fallback, int* retval);

#endif