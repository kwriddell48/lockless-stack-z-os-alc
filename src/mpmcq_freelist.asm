         TITLE 'MPMC stack - Lock-free freelist for node reuse (tagged pointer CDS)'
***********************************************************************
*  MPMCQ_FREELIST.ASM
*
*  Implements a lock-free stack (Treiber) used as a node pool.
*  This is an internal component: nodes are never returned to the system
*  here; they are re-used by pushing/popping from SCB_FREE_(ABA,PTR).
*
*  ABA mitigation:
*    - The freelist head is a tagged pointer (ABA32, PTR31).
*    - Pop/push update the pair atomically with CDS.
*
*  Reentrancy:
*    - No static work areas; this module is safe RENT/reentrant.
*    - All shared state is in the caller's SCB (SCB_FREE_ABA/SCB_FREE_PTR).
*
*  Exported internal entry points:
*    MPMCS_POPNODE(SCBaddr)  -> R15=0 and R1=node or R15=4 empty
*    MPMCS_PUSHNODE(SCBaddr,node) -> R15=0
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_atomics.mac'

MPMCQFL  CSECT
MPMCQFL  AMODE 31
MPMCQFL  RMODE ANY

         ENTRY MPMCS_POPNODE
         ENTRY MPMCS_PUSHNODE

         USING MPMCQFL,R15

***********************************************************************
* MPMCS_POPNODE
*   Input:  Q_R = SCBaddr
*   Returns:
*     R15=0 success, R1=node address
*     R15=4 empty
***********************************************************************
MPMCS_POPNODE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQFL,12
         USING MPMCS_SCB,Q_R

POPN_LOOP DS 0H
* Expected head (ABA,PTR) from SCB.
* If PTR is zero, freelist is empty.
         L     R0,SCB_FREE_ABA
         LT    R1,SCB_FREE_PTR
         JZ    POPN_EMPTY

* Snapshot the node pointed to by the freelist head.
* NOTE: The pointer may change under us; CDS below validates the expected pair.
         LR    NODE_R,R1                 node = old_ptr
         USING MPMCQ_NODE,NODE_R

* Desired head becomes (node->next_aba, node->next_ptr).
* (We keep ABA from node->next; the head ABA itself is refreshed below.)
         L     R6,NODE_NEXT_ABA
         L     R7,NODE_NEXT_PTR

* Refresh ABA tag for freelist head update: ABA = SCB_ABA_SEQ++
POP_ABA_LOOP DS 0H
         L     R8,SCB_ABA_SEQ
         LA    R9,1(R8)
         CS    R8,R9,SCB_ABA_SEQ
         JNE   POP_ABA_LOOP
         LR    R6,R9                     desired ABA tag
         * desired PTR already in R7

* CAS SCB_FREE from expected (R0,R1) to desired (ABA,PTR).
* On failure, someone else won; retry with the new observed head.
         CDS   R0,R6,SCB_FREE_ABA(Q_R)
         JNE   POPN_LOOP

* Success: return node in R1
         LR    R1,NODE_R
         XR    R15,R15
         LM    R14,R12,12(R13)
         BR    R14

POPN_EMPTY DS 0H
         LA    R15,4
         LM    R14,R12,12(R13)
         BR    R14

***********************************************************************
* MPMCS_PUSHNODE
*   Input:  Q_R = SCBaddr
*           NEWNODE_R = node address
*   Returns R15=0
***********************************************************************
MPMCS_PUSHNODE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQFL,12
         USING MPMCS_SCB,Q_R
         USING MPMCQ_NODE,NEWNODE_R

PUSHN_LOOP DS 0H
* Expected head (ABA,PTR) from SCB.
         L     R0,SCB_FREE_ABA
         L     R1,SCB_FREE_PTR

* Link the pushed node to the current head.
* We store the head ABA/PTR into NODE_NEXT_(ABA,PTR).
         ST    R0,NODE_NEXT_ABA
         ST    R1,NODE_NEXT_PTR

* Desired new head = (newABA, node_ptr).
PUSH_ABA_LOOP DS 0H
         L     R8,SCB_ABA_SEQ
         LA    R9,1(R8)
         CS    R8,R9,SCB_ABA_SEQ
         JNE   PUSH_ABA_LOOP
         LR    R10,R9                    desired ABA
         LR    R11,NEWNODE_R             desired PTR

* CAS SCB_FREE from expected (R0,R1) to desired (ABA,PTR).
* On failure, head changed; rewrite node->next_ptr and retry.
         CDS   R0,R10,SCB_FREE_ABA(Q_R)
         JNE   PUSHN_LOOP

         XR    R15,R15
         LM    R14,R12,12(R13)
         BR    R14

         END   MPMCQFL

