         TITLE 'Test notifier callback - add PendingCount at CB_CTX'
***********************************************************************
*  TESTCB.ASM
*
*  Called by MPMCS_NOTIF with R1 -> (CB_CTX, SCBaddr, PendingCount).
*  CB_CTX is a fullword counter (31-bit). Atomically add PendingCount.
***********************************************************************
TESTCB   CSECT
TESTCB   AMODE 31
TESTCB   RMODE ANY
         ENTRY TESTCB
         STM   14,12,12(13)
         LR    12,15
         USING TESTCB,12
         L     2,0(,1)
         L     3,8(,1)
         L     0,0(,2)
TLOOP    DS    0H
         LR    4,0
         AR    4,3
         CS    0,4,0(2)
         BRC   4,TLOOP
         LM    14,12,12(13)
         BR    14
         END   TESTCB
