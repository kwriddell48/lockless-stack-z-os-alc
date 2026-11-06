         TITLE 'STAT64T - STATADD64 / STATADD64S / STATMAX64 harness'
***********************************************************************
*  STAT64T.ASM
*
*  OS-linkage test entries for the 64-bit counter macros.
*  R1 -> plist. DWADDR must be 8-byte aligned (CDS). Big-endian
*  layout matches C uint64_t on z/OS.
***********************************************************************
         PRINT GEN
         COPY  REGEQUAT
         COPY  ATOMICS

STAT64T  CSECT
STAT64T  AMODE 31
STAT64T  RMODE ANY
         ENTRY S64ADD,S64ADDS,S64MAX

S64ADD   DS    0H
         STM   R14,R12,12(R13)
         LARL  R12,STAT64T
         USING STAT64T,R12
         L     R3,0(,R1)
         TMLL  R3,X'0007'
         JNZ   S64_ALIGN
         L     R7,4(,R1)
         USING S64DW,R3
         MPMCQ_STATADD64 0,S64HI,S64LO,R7,R0,R8
         DROP  R3
         XR    R15,R15
         ST    R15,16(R13)
         LM    R14,R12,12(R13)
         BR    R14

S64ADDS  DS    0H
         STM   R14,R12,12(R13)
         LARL  R12,STAT64T
         USING STAT64T,R12
         L     R3,0(,R1)
         TMLL  R3,X'0007'
         JNZ   S64_ALIGN
         L     R7,4(,R1)
         USING S64DW,R3
         MPMCQ_STATADD64S 0,S64HI,S64LO,R7,R0,R8
         DROP  R3
         XR    R15,R15
         ST    R15,16(R13)
         LM    R14,R12,12(R13)
         BR    R14

S64MAX   DS    0H
         STM   R14,R12,12(R13)
         LARL  R12,STAT64T
         USING STAT64T,R12
         L     R3,0(,R1)
         TMLL  R3,X'0007'
         JNZ   S64_ALIGN
         L     R4,4(,R1)
         L     R6,8(,R1)
         USING S64DW,R3
         MPMCQ_STATMAX64 0,S64HI,S64LO,R4,R6,R0,R8
         DROP  R3
         XR    R15,R15
         ST    R15,16(R13)
         LM    R14,R12,12(R13)
         BR    R14

S64_ALIGN DS   0H
         LA    R15,8
         ST    R15,16(R13)
         LM    R14,R12,12(R13)
         BR    R14

S64DW    DSECT
S64HI    DS    F
S64LO    DS    F
         END   STAT64T
