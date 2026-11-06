/* T03LIFO - three pushes, pops come back in reverse order. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    char out[8];
    uint32_t n = 0;
    int32_t rc;

    printf("T03LIFO start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    TEST_RC(mpmcs_spush(scb, "A", 1), MPMCS_RC_OK, "push A");
    TEST_RC(mpmcs_spush(scb, "B", 1), MPMCS_RC_OK, "push B");
    TEST_RC(mpmcs_spush(scb, "C", 1), MPMCS_RC_OK, "push C");

    memset(out, 0, sizeof(out));
    n = 0;
    rc = mpmcs_spop(scb, out, 1, &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop 1");
    TEST_EXPECT(n == 1 && out[0] == 'C', "expected C");

    memset(out, 0, sizeof(out));
    n = 0;
    rc = mpmcs_spop(scb, out, 1, &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop 2");
    TEST_EXPECT(n == 1 && out[0] == 'B', "expected B");

    memset(out, 0, sizeof(out));
    n = 0;
    rc = mpmcs_spop(scb, out, 1, &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop 3");
    TEST_EXPECT(n == 1 && out[0] == 'A', "expected A");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T03LIFO PASS\n");
    mpmcs_free(scb);
    return 0;
}
