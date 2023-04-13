
  include ../common-forth/nucleus-16kb-dualport.fs

\ -----------------------------------------------------------------------------
\  Boot here
\ -----------------------------------------------------------------------------

: main
    dint     \ Disable interrupts
    welcome   \ Emit welcome message

    init @ ?dup if execute then \ The freshly loaded image might have init set
    quit
;

meta
    link @ t' forth tw!
    there  t' dp tw!
target
