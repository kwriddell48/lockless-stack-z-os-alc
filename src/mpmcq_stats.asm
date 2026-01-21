         TITLE 'MPMC stack - SSTATS snapshot routine'
***********************************************************************
*  MPMCQ_STATS.ASM
*
*  SSTATS(SCBaddr, outStatsAddr, outStatsLen)
*   - Copies a versioned stats snapshot to caller buffer.
*   - Stats are approximate under concurrency; this is a best-effort snapshot.
*
*  Snapshot semantics:
*   - No global lock is taken (stack remains lock-free).
*   - Individual counters are read and stored; values can be slightly skewed
*     relative to each other if producers/consumers are updating concurrently.
*   - outStatsLen allows forward-compatible extension of the stats DSECT.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'

MPMCQST  CSECT
MPMCQST  AMODE 31
MPMCQST  RMODE ANY

         ENTRY SSTATS
         USING MPMCQST,R15

SSTATS   DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQST,12

         L     R4,SST_OUTLEN(R1)
         LT    Q_R,SST_SCBADDR(R1)
         JZ    QST_DONE
         LT    R3,SST_OUTADDR(R1)
         JZ    QST_DONE

         USING MPMCS_SCB,Q_R
         USING MPMCS_STATS,R3

* Determine how many bytes we can copy
         LA    R5,STATS_END-MPMCS_STATS
         CR    R4,R5
         JNH   QST_LEN_OK
         LR    R4,R5
QST_LEN_OK DS 0H

         MVC   STATS_VERSION,=F'MPMCS_STATS_VERSION'
         ST    R4,STATS_SIZE

* Copy fullword counters
         L     R0,SCB_STAT_PUSH_OK
         ST    R0,STATS_PUSH_OK
         L     R0,SCB_STAT_POP_OK
         ST    R0,STATS_POP_OK
         L     R0,SCB_STAT_POP_EMPTY
         ST    R0,STATS_POP_EMPTY
         L     R0,SCB_STAT_PUSH_ALLOC_FAIL
         ST    R0,STATS_PUSH_ALLOC_FAIL

         L     R0,SCB_STAT_PUSH_RETRY
         ST    R0,STATS_PUSH_RETRY
         L     R0,SCB_STAT_POP_RETRY
         ST    R0,STATS_POP_RETRY
         L     R0,SCB_STAT_FREELIST_POP_RETRY
         ST    R0,STATS_FREELIST_POP_RETRY
         L     R0,SCB_STAT_FREELIST_PUSH_RETRY
         ST    R0,STATS_FREELIST_PUSH_RETRY

         L     R0,SCB_STAT_DEPTH_CUR
         ST    R0,STATS_DEPTH_CUR
         L     R0,SCB_STAT_DEPTH_MAX
         ST    R0,STATS_DEPTH_MAX

* Copy 31-bit payload byte counters (hi/lo -> D)
         L     R0,SCB_STAT_PAYLOAD31_CUR_HI
         ST    R0,STATS_PAYLOAD31_CUR
         L     R0,SCB_STAT_PAYLOAD31_CUR_LO
         ST    R0,STATS_PAYLOAD31_CUR+4
         L     R0,SCB_STAT_PAYLOAD31_MAX_HI
         ST    R0,STATS_PAYLOAD31_MAX
         L     R0,SCB_STAT_PAYLOAD31_MAX_LO
         ST    R0,STATS_PAYLOAD31_MAX+4

* Copy 64-bit payload byte counters (hi/lo -> D)
         L     R0,SCB_STAT_PAYLOAD64_CUR_HI
         ST    R0,STATS_PAYLOAD64_CUR
         L     R0,SCB_STAT_PAYLOAD64_CUR_LO
         ST    R0,STATS_PAYLOAD64_CUR+4
         L     R0,SCB_STAT_PAYLOAD64_MAX_HI
         ST    R0,STATS_PAYLOAD64_MAX
         L     R0,SCB_STAT_PAYLOAD64_MAX_LO
         ST    R0,STATS_PAYLOAD64_MAX+4

         L     R0,SCB_STAT_POST_INTERNAL
         ST    R0,STATS_POST_INTERNAL
         L     R0,SCB_STAT_POST_USERECB
         ST    R0,STATS_POST_USERECB
         L     R0,SCB_STAT_CB_CALLS
         ST    R0,STATS_CB_CALLS
         L     R0,SCB_STAT_CB_PENDING_MAX
         ST    R0,STATS_CB_PENDING_MAX

QST_DONE DS 0H
         XR    R15,R15
         LM    R14,R12,12(R13)
         BR    R14

         END   MPMCQST

