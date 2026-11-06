/* T02INIT - SINIT writes the SCB eyecatcher; SCBSTOP is a no-op. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    int32_t rc;

    printf("T02INIT start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");

    rc = mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0);
    TEST_RC(rc, MPMCS_RC_OK, "SINIT");
    TEST_EXPECT(mpmcs_check_eye(scb), "eyecatcher not MPMCSTK ");

    rc = mpmcs_scbstop(scb);
    TEST_RC(rc, MPMCS_RC_OK, "SCBSTOP");

    printf("T02INIT PASS\n");
    mpmcs_free(scb);
    return 0;
}
