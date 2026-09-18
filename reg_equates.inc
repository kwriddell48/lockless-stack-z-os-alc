         TITLE 'Register equates (R0-R15)'
***********************************************************************
*  REG_EQUATES.INC
*
*  Standard z/Architecture register equates for readability.
***********************************************************************
R0       EQU   0
R1       EQU   1
R2       EQU   2
R3       EQU   3
R4       EQU   4
R5       EQU   5
R6       EQU   6
R7       EQU   7
R8       EQU   8
R9       EQU   9
R10      EQU   10
R11      EQU   11
R12      EQU   12
R13      EQU   13
R14      EQU   14
R15      EQU   15

***********************************************************************
* Role-based register aliases (readability)
*
* Convention used by this project:
* - Q_R:    base register holding the Stack Control Block (SCB) address
* - NODE_R: base register holding the current Node address when referencing
*           node fields via DSECT offsets.
***********************************************************************
Q_R        EQU   R2

* Stack implementation uses multiple node pointers at once; keep separate roles:
* - NODE_R:      \"current\" node being dereferenced via DSECT offsets
* - NEWNODE_R:   newly allocated node to be pushed / node being recycled
* - NEXTNODE_R:  next node pointer during traversal
NODE_R     EQU   R10
NEWNODE_R  EQU   R5
NEXTNODE_R EQU   R3