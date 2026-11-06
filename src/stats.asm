         TITLE 'MPMC stack - SSTATS snapshot routine'
***********************************************************************
*  STATS.ASM
*
*  SSTATS(SCBaddr, outStatsAddr, outStatsLen)
*    R1 -> parm list (see MPMCS_SSTATS_PLIST in dsects.inc).
***********************************************************************

         PRINT GEN

         COPY  REGEQUAT
         COPY  DSECTS
         COPY  SAVEMAC

MPMCQST  CSECT
MPMCQST  AMODE 31
MPMCQST  RMODE ANY

         ENTRY SSTATS
         USING MPMCQST,R15

ST_SA      EQU   0
ST_OUTA    EQU   72
ST_OUTL    EQU   76
ST_SNAP    EQU   80
ST_SNAPLEN EQU   STATS_END-MPMCS_STATS
ST_WLEN    EQU   ST_SNAP+ST_SNAPLEN

SSTATS   DS 0H
         MPMCQ_ENTER ST_WLEN,MPMCQST
         USING MPMCQST,R12
         USING MPMCS_SSTATS_PLIST,R1

         L     R4,SST_OUTLEN
         LT    Q_R,SST_SCBADDR
         JZ    QST_DONE                    no SCB => nothing to report
         LT    R3,SST_OUTADDR
         JZ    QST_DONE                    no output buffer
         ST    R3,ST_OUTA(R13)
         ST    R4,ST_OUTL(R13)
         DROP  R1

         USING MPMCS_SCB,Q_R
         LA    R3,ST_SNAP(R13)             R3 -> private snapshot
         USING MPMCS_STATS,R3

         LA    R5,ST_SNAPLEN
         LA    R0,MPMCS_STATS_VERSION
         ST    R0,STATS_VERSION
         ST    R5,STATS_SIZE

         L     R0,SCB_PUSH_SEQ
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

* LG is doubleword-atomic; LM is only word-concurrent.
         LG    R0,SCB_STAT_PAYLOAD31_CUR_HI
         STG   R0,STATS_PAYLOAD31_CUR
         LG    R0,SCB_STAT_PAYLOAD31_MAX_HI
         STG   R0,STATS_PAYLOAD31_MAX
         LG    R0,SCB_STAT_PAYLOAD64_CUR_HI
         STG   R0,STATS_PAYLOAD64_CUR
         LG    R0,SCB_STAT_PAYLOAD64_MAX_HI
         STG   R0,STATS_PAYLOAD64_MAX

         L     R0,SCB_STAT_POST_INTERNAL
         ST    R0,STATS_POST_INTERNAL
         L     R0,SCB_STAT_POST_USERECB
         ST    R0,STATS_POST_USERECB
         L     R0,SCB_STAT_CB_CALLS
         ST    R0,STATS_CB_CALLS
         L     R0,SCB_STAT_CB_PENDING_MAX
         ST    R0,STATS_CB_PENDING_MAX

         L     R4,ST_OUTL(R13)
         LA    R5,ST_SNAPLEN
         CLR   R4,R5
         JNH   QST_LEN_OK
         LR    R4,R5
QST_LEN_OK DS 0H
         LTR   R4,R4
         JZ    QST_DONE
         ST    R4,STATS_SIZE

         L     R8,ST_OUTA(R13)
         LR    R9,R4
         LA    R10,ST_SNAP(R13)
         LR    R11,R4
         MVCL  R8,R10

QST_DONE DS 0H
         XR    R15,R15
         MPMCQ_RETURN R15,ST_WLEN

         LTORG
         END   MPMCQST
