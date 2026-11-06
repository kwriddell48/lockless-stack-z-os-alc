/* T10ECB - user ECB is POSTed on successful SPUSH. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    volatile uint32_t ecb = 0;
    char out[8];
    uint32_t n = 0;
    MpmcsStats st;

    printf("T10ECB start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, (void *)&ecb),
            MPMCS_RC_OK, "SINIT");

    TEST_EXPECT(ecb == 0, "ECB not zero at start");
    TEST_RC(mpmcs_spush(scb, "E", 1), MPMCS_RC_OK, "push");
    TEST_EXPECT(ecb != 0, "user ECB was not POSTed");

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.post_userecb >= 1, "POST_USERECB counter");
    /* Internal POST is only issued when SINIT got a callback EP. */

    TEST_RC(mpmcs_spop(scb, out, 1, &n), MPMCS_RC_OK, "pop");
    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T10ECB PASS ecb=0x%08X posts=%u\n",
           (unsigned)ecb, (unsigned)st.post_userecb);
    mpmcs_free(scb);
    return 0;
}
