         TITLE 'MPMC stack - SSTATS snapshot routine'
***********************************************************************
*  MPMCQ_STATS.ASM
*
*  SSTATS(SCBaddr, outStatsAddr, outStatsLen)
*    R1 -> parm list (see MPMCS_SSTATS_PLIST in mpmcq_dsects.inc).
*
*  Purpose:
*    Copy a versioned statistics snapshot to a caller buffer without
*    taking a global lock (stack remains lock-free). Counters can be
*    slightly skewed relative to each other under concurrency — that is
*    intentional (best-effort / approximate).
*
*  Buffer safety:
*    We build the FULL snapshot in a private work-area buffer first, then
*    MVCL only min(outStatsLen, snapshot_size) bytes to the caller.
*    STATS_SIZE in the snapshot is set to the number of bytes provided
*    to the caller (so short buffers still get a coherent prefix).
*
*  Null SCB or null outAddr => no-op, RC=0.
*
*  Note: STATS_PUSH_OK is sourced from SCB_PUSH_SEQ, not a separate
*  SCB_STAT_PUSH_OK counter. Both used to count the same event (a
*  successful SPUSH); SCB_PUSH_SEQ already existed for notifier
*  coalescing, so the redundant stat increment was retired in
*  MPMCQ.ASM's SPU_PUSH_OK path.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_save.mac'

MPMCQST  CSECT
MPMCQST  AMODE 31
MPMCQST  RMODE ANY

         ENTRY SSTATS
         USING MPMCQST,R15

***********************************************************************
* Work area: SA + caller out pointer/len + inline snapshot buffer.
* ST_SNAPLEN tracks the MPMCS_STATS DSECT size for forward compatibility.
***********************************************************************
ST_SA      EQU   0
ST_OUTA    EQU   72                      caller outStatsAddr
ST_OUTL    EQU   76                      caller outStatsLen
ST_SNAP    EQU   80                      start of private MPMCS_STATS image
ST_SNAPLEN EQU   STATS_END-MPMCS_STATS
ST_WLEN    EQU   ST_SNAP+ST_SNAPLEN

SSTATS   DS 0H
         MPMCQ_ENTER ST_WLEN
         USING MPMCQST,12

         L     R4,SST_OUTLEN(R1)
         LT    Q_R,SST_SCBADDR(R1)
         JZ    QST_DONE                    no SCB => nothing to report
         LT    R3,SST_OUTADDR(R1)
         JZ    QST_DONE                    no output buffer
         ST    R3,ST_OUTA(R13)
         ST    R4,ST_OUTL(R13)

         USING MPMCS_SCB,Q_R
         LA    R3,ST_SNAP(R13)             R3 -> private snapshot
         USING MPMCS_STATS,R3

* Header: version + provisional full size (may shrink before MVCL).
         LA    R5,ST_SNAPLEN
         MVC   STATS_VERSION,=F'MPMCS_STATS_VERSION'
         ST    R5,STATS_SIZE

*----- Fullword counters (unlocked loads; may tear vs each other) -----
         L     R0,SCB_PUSH_SEQ              was SCB_STAT_PUSH_OK (merged)
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

*----- 64-bit payload byte counters stored as adjacent F in SCB -------
* Snapshot layout uses DS D; copy HI then LO into each doubleword.
         L     R0,SCB_STAT_PAYLOAD31_CUR_HI
         ST    R0,STATS_PAYLOAD31_CUR
         L     R0,SCB_STAT_PAYLOAD31_CUR_LO
         ST    R0,STATS_PAYLOAD31_CUR+4
         L     R0,SCB_STAT_PAYLOAD31_MAX_HI
         ST    R0,STATS_PAYLOAD31_MAX
         L     R0,SCB_STAT_PAYLOAD31_MAX_LO
         ST    R0,STATS_PAYLOAD31_MAX+4

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

*----- Bounded copy to caller ----------------------------------------
         L     R4,ST_OUTL(R13)
         LA    R5,ST_SNAPLEN
         CR    R4,R5
         JNH   QST_LEN_OK
         LR    R4,R5                       R4 = bytes we will deliver
QST_LEN_OK DS 0H
         LTR   R4,R4
         JZ    QST_DONE
         ST    R4,STATS_SIZE               report delivered length

         L     R8,ST_OUTA(R13)             dest
         LR    R9,R4
         LA    R10,ST_SNAP(R13)            src = private snapshot
         LR    R11,R4
         MVCL  R8,R10                      equal lengths => no padding

QST_DONE DS 0H
         XR    R15,R15
         MPMCQ_RETURN R15,ST_WLEN

         END   MPMCQST
