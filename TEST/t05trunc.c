/* T05TRUNC - short dest copies prefix, RC=8, outLen is full length. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    char out[4];
    uint32_t n = 0;
    int32_t rc;
    const char *msg = "ABCDEFGH";

    printf("T05TRUNC start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    TEST_RC(mpmcs_spush(scb, msg, 8), MPMCS_RC_OK, "push 8");

    memset(out, 0xFF, sizeof(out));
    rc = mpmcs_spop(scb, out, 3, &n);
    TEST_RC(rc, MPMCS_RC_TRUNC, "truncated pop");
    TEST_EXPECT(n == 8, "outLen is not the full message length");
    TEST_EXPECT(memcmp(out, "ABC", 3) == 0, "truncated prefix");

    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &n),
            MPMCS_RC_EMPTY, "empty after truncated pop");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T05TRUNC PASS\n");
    mpmcs_free(scb);
    return 0;
}
