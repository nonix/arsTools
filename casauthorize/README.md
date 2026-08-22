to compile:
gcc -fPIC -m64 -O2 -shared \
    -I$HOME/sqllib/include casauthorize.c \
    -o $HOME/sqllib/function/libcasauthorize.so -lcurl

to configure:
#define AUTH_TTL_SECONDS   5400
#define AUTH_MAX_ENTRIES   100
#define BCNR_LEN           4
#define KONTO_MAX          8
#define AUTH_KEY_LEN       (BCNR_LEN + KONTO_MAX)        /* 12 bytes */
#define AUTH_RECORD_LEN    (AUTH_KEY_LEN + 1)            /* 13 bytes */
#define AUTH_BUCKET_BYTES  (4 + (AUTH_MAX_ENTRIES * AUTH_RECORD_LEN)) /* 1304 */
#define REST_URL           "http://localhost:8000/authorize"
#define REST_TIMEOUT_SEC   5L
#define MSG_LEN            1024
