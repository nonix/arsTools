Implements a simple DB2 function for CMOD to convert string in format of YYYYMMDD to arsdate. If string is not convertable, takes fallback value.
To compile:
 gcc -s -fPIC -fvisibility=hidden  -shared str2arsdate.c -o liblah.so
 
