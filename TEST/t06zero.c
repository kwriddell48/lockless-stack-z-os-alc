/* T06ZERO - zero-length push is valid; pop returns len 0. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    char out[4];
    uint32_t n = 99;
    int32_t rc;

    printf("T06ZERO start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    TEST_RC(mpmcs_spush(scb, "", 0), MPMCS_RC_OK, "push len 0");
    TEST_RC(mpmcs_spush(scb, "Z", 1), MPMCS_RC_OK, "push Z");

    memset(out, 0xAA, sizeof(out));
    n = 0;
    rc = mpmcs_spop(scb, out, sizeof(out), &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop Z");
    TEST_EXPECT(n == 1 && out[0] == 'Z', "expected Z on top");

    n = 99;
    rc = mpmcs_spop(scb, out, sizeof(out), &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop zero-length");
    TEST_EXPECT(n == 0, "zero-length outLen");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T06ZERO PASS\n");
    mpmcs_free(scb);
    return 0;
}
