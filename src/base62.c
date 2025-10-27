#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(void) {
    const unsigned char data[] = { 0x00, 0x01, 0x02, 0xFF };
    size_t dlen = sizeof(data);

    /* Get required size */
    size_t needed = base62_encode(data, dlen, NULL, 0);
    char *enc = malloc(needed + 1);
    base62_encode(data, dlen, enc, needed + 1);
    printf("encoded: %s\n", enc);

    /* decode */
    ssize_t decoded_len = base62_decode(enc, NULL, 0);
    unsigned char *decoded = malloc(decoded_len);
    ssize_t wr = base62_decode(enc, decoded, decoded_len);
    printf("decoded bytes (%zd):", wr);
    for (ssize_t i=0;i<wr;++i) printf(" %02X", decoded[i]);
    printf("\n");

    free(enc);
    free(decoded);
    return 0;
}
