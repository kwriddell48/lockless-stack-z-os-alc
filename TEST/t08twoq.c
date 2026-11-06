/* T08TWOQ - two SCBs are independent stacks. */
#include "mpmcs.h"

int main(void)
{
    void *a;
    void *b;
    char out[8];
    uint32_t n = 0;

    printf("T08TWOQ start\n");
    fflush(stdout);

    a = mpmcs_alloc_scb();
    b = mpmcs_alloc_scb();
    TEST_EXPECT(a != NULL && b != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(a, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT A");
    TEST_RC(mpmcs_sinit(b, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT B");

    TEST_RC(mpmcs_spush(a, "A1", 2), MPMCS_RC_OK, "push A");
    TEST_RC(mpmcs_spush(b, "B1", 2), MPMCS_RC_OK, "push B");
    TEST_RC(mpmcs_spush(a, "A2", 2), MPMCS_RC_OK, "push A2");

    n = 0;
    TEST_RC(mpmcs_spop(b, out, sizeof(out), &n), MPMCS_RC_OK, "pop B");
    TEST_EXPECT(n == 2 && memcmp(out, "B1", 2) == 0, "B isolated");
    TEST_RC(mpmcs_spop(b, out, sizeof(out), &n),
            MPMCS_RC_EMPTY, "B drained");

    n = 0;
    TEST_RC(mpmcs_spop(a, out, sizeof(out), &n), MPMCS_RC_OK, "pop A2");
    TEST_EXPECT(n == 2 && memcmp(out, "A2", 2) == 0, "A2");
    n = 0;
    TEST_RC(mpmcs_spop(a, out, sizeof(out), &n), MPMCS_RC_OK, "pop A1");
    TEST_EXPECT(n == 2 && memcmp(out, "A1", 2) == 0, "A1");

    TEST_RC(mpmcs_scbstop(a), MPMCS_RC_OK, "SCBSTOP A");
    TEST_RC(mpmcs_scbstop(b), MPMCS_RC_OK, "SCBSTOP B");
    printf("T08TWOQ PASS\n");
    mpmcs_free(a);
    mpmcs_free(b);
    return 0;
}
