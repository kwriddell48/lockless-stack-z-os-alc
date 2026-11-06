/* T04EMPTY - pop empty RC=4; still empty after a push/pop. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    char out[8];
    uint32_t n = 99;
    int32_t rc;

    printf("T04EMPTY start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    rc = mpmcs_spop(scb, out, sizeof(out), &n);
    TEST_RC(rc, MPMCS_RC_EMPTY, "pop empty stack");

    TEST_RC(mpmcs_spush(scb, "X", 1), MPMCS_RC_OK, "push");
    n = 0;
    TEST_RC(mpmcs_spop(scb, out, 1, &n), MPMCS_RC_OK, "pop X");
    TEST_EXPECT(n == 1 && out[0] == 'X', "round-trip X");

    rc = mpmcs_spop(scb, out, sizeof(out), &n);
    TEST_RC(rc, MPMCS_RC_EMPTY, "pop after drain");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T04EMPTY PASS\n");
    mpmcs_free(scb);
    return 0;
}
