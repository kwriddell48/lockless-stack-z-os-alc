/* T11CB - notifier TCB calls TESTCB; pending counts accumulate. */
#include "mpmcs.h"

#ifdef __MVS__
#pragma linkage(CTESTEP, OS)
#endif
extern void CTESTEP(void **out);

int main(void)
{
    void *scb;
    void *cb;
    volatile uint32_t seen = 0;
    char out[8];
    uint32_t n = 0;
    MpmcsStats st;
    int i;
    int spins;

    printf("T11CB start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    cb = 0;
    CTESTEP(&cb);
    TEST_EXPECT(cb != 0, "TESTCB address");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31,
                        cb, (void *)&seen, 0),
            MPMCS_RC_OK, "SINIT with callback");

    for (i = 0; i < 5; i++)
        TEST_RC(mpmcs_spush(scb, "C", 1), MPMCS_RC_OK, "push");

    /* Notifier is a separate TCB. Poll until it has observed pushes. */
    for (spins = 0; spins < 200 && seen == 0; spins++) {
        TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS poll");
        if (st.cb_calls > 0)
            break;
        mpmcs_spin(400000u);
    }

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.cb_calls >= 1, "notifier never called TESTCB");
    TEST_EXPECT(seen >= 1, "TESTCB counter still 0");
    TEST_EXPECT(seen <= 5, "TESTCB counter > pushes");

    printf("cb_calls=%u pending_max=%u seen=%u\n",
           (unsigned)st.cb_calls, (unsigned)st.cb_pending_max,
           (unsigned)seen);
    fflush(stdout);

    printf("T11CB pops\n");
    fflush(stdout);
    for (i = 0; i < 5; i++)
        TEST_RC(mpmcs_spop(scb, out, 1, &n), MPMCS_RC_OK, "pop");

    printf("T11CB scbstop\n");
    fflush(stdout);
    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T11CB PASS\n");
    mpmcs_free(scb);
    return 0;
}
