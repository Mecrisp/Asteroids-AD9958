
\ Definitions in high-level Forth that can be compiled by the small
\ nucleus itself. They are included into the bitstream for default.

\ #######   CORE   ############################################

: [']
    '
; immediate 0 foldable

: [char]
    char
; immediate 0 foldable

: (
    [char] ) parse 2drop
; immediate 0 foldable

: u>= ( u1 u2 -- ? ) u< invert ; 2 foldable
: u<= ( u1 u2 -- ? ) u> invert ; 2 foldable
: >=  ( n1 n2 -- ? )  < invert ; 2 foldable
: <=  ( n1 n2 -- ? )  > invert ; 2 foldable

: else
    postpone ahead
    swap
    postpone then
; immediate

: while
    postpone if
    swap
; immediate

: repeat
     postpone again
     postpone then
; immediate

: create ( "<name>" -- ; -- addr )
    :
    here 2 cells + postpone literal
    postpone ;
;

: buffer: ( u "<name>" -- ; -- addr )
   create allot 0 foldable
;

: >body ( addr -- addr' )
    @ -1 1 rshift and \ Remove the literal opcode MSB
;

: m* ( n1 n2 -- d )
    2dup xor >r
    abs swap abs um*
    r> 0< if dnegate then
; 2 foldable

: variable ( x "name" -- ; -- addr )
    create ,
    0 foldable
;

: constant ( x "name" -- ; -- x ) : postpone literal postpone ; 0 foldable ;

: sgn ( u1 n1 -- n2 ) \ n2 is u1 with the sign of n1
    0< if negate then
; 2 foldable

\ Divide d1 by n1, giving the symmetric quotient n3 and the remainder
\ n2.
: sm/rem ( d1 n1 -- n2 n3 )
    2dup xor >r     \ combined sign, for quotient
    over >r         \ sign of dividend, for remainder
    abs >r dabs r>
    um/mod          ( remainder quotient )
    swap r> sgn     \ apply to remainder
    swap r> sgn     \ apply to quotient
; 3 foldable

\ Divide d1 by n1, giving the floored quotient n3 and the remainder n2.
\ Adapted from hForth
: fm/mod ( d1 n1 -- n2 n3 )
    dup >r 2dup xor >r
    >r dabs r@ abs
    um/mod
    r> 0< if
        swap negate swap
    then
    r> 0< if
        negate         \ negative quotient
        over if
            r@ rot - swap 1-
        then
    then
    r> drop
; 3 foldable

: */mod ( n1 n2 n3 -- n4 n5 ) >r m* r> sm/rem ; 3 foldable
: */    ( n1 n2 n3 -- n4 )    */mod nip ; 3 foldable

: spaces ( n -- )
    begin
        dup 0>
    while
        space 1-
    repeat
    drop
;

( Pictured numeric output                    JCB 08:06 07/18/14)
\ Adapted from hForth

\ "The size of the pictured numeric output string buffer shall
\ be at least (2*n) + 2 characters, where n is the number of
\ bits in a cell."

create BUF0
16 cells 2 + 128 max
allot here constant BUF

0 variable hld

: <# ( -- )
    BUF hld !
;

: hold ( c -- )
    hld @ 1- dup hld ! c!
;

: sign ( n -- )
    0< if
        [char] - hold
    then
;

: .digit ( u -- c )
  9 over <
  [char] A [char] 9 1 + -
  and +
  [char] 0 +
;

: # ( ud -- ud* )
    0 base @ um/mod >r base @ um/mod swap
    .digit hold r>
;

: #s ( ud -- 0 0 )
    begin
        #
        2dup d0=
    until
;

: #> ( ud -- addr len )
    2drop hld @ BUF over -
;

: (d.) ( d -- addr len )
    dup >r dabs <# #s r> sign #>
;

: ud. ( ud -- )
    <# #s #> type space
;

: d. ( d -- )
    (d.) type space
;

: . ( n -- )
    s>d d.
;

: u. ( u -- )
    0 d.
;

: rtype ( caddr u1 u2 -- ) \ display character string specified by caddr u1
                           \ in a field u2 characters wide.
  2dup u< if over - spaces else drop then
  type
;

: d.r ( d length -- )
    >r (d.)
    r> rtype
;

: .r ( n length -- )
    >r s>d r> d.r
;

: u.r ( u length -- )
    0 swap d.r
;

( Memory operations                          JCB 18:02 05/31/15)

: move ( addr1 addr2 u -- )
    >r 2dup u< if
        r> cmove>
    else
        r> cmove
    then
;

: /mod ( n1 n2 -- n3 n4 ) >r s>d r> sm/rem ; 2 foldable
: /    ( n1 n2 -- n3 )    /mod nip ; 2 foldable
: mod  ( n1 n2 -- n3 )    /mod drop ; 2 foldable

: ."
    [char] " parse
    state @ if
        postpone sliteral
        postpone type
    else
        type
    then
; immediate 0 foldable

\ #######   CORE EXT   ########################################

: pad ( -- addr )
    here aligned
;

: within ( n1|u1 n2|u2 n3|u3 -- flag ) over - >r - r> u< ; 3 foldable

: s"
    [char] " parse
    state @ if
        postpone sliteral
    then
; immediate

( CASE                                       JCB 09:15 07/18/14)
\ From ANS specification A.3.2.3.2

: case ( -- 0 ) 0 ; immediate  ( init count of ofs )

: of  ( #of -- orig #of+1 / x -- )
    1+    ( count ofs )
    >r    ( move off the stack in case the control-flow )
          ( stack is the data stack. )
    postpone over  postpone = ( copy and test case value)
    postpone if    ( add orig to control flow stack )
    postpone drop  ( discards case value if = )
    r>             ( we can bring count back now )
; immediate

: endof ( orig1 #of -- orig2 #of )
    >r   ( move off the stack in case the control-flow )
         ( stack is the data stack. )
    postpone else
    r>   ( we can bring count back now )
; immediate

: endcase  ( orig1..orign #of -- )
    postpone drop  ( discard case value )
    0 ?do
      postpone then
    loop
; immediate

\ #######   DICTIONARY   ######################################

: cornerstone ( "name" -- )
  create
    forth 2@        \ preserve FORTH and DP after this
    , 2 cells + ,
  does>
    2@ forth 2! \ restore FORTH and DP
;
\ #######   MEMORY   ##########################################

: unused ( -- u ) $4000 here - ;

\ #######   IO   ##############################################

: randombit ( -- 0 | 1 ) $2000 io@ 2 rshift 1 and ;
: random ( -- x ) 0  16 0 do 2* randombit or 100 0 do loop loop ;

: ticks ( -- u ) $4000 io@ ;

: nextirq ( cycles -- ) \ Trigger the next interrupt u cycles after the last one.
  $4000 io@  \ Read current tick
  -           \ Subtract the cycles already elapsed
  8 -          \ Correction for the cycles neccessary to do this
  invert        \ Timer counts up to zero to trigger the interrupt
  $4000 io!      \ Prepare timer for the next irq
;

: reset ( -- ) 1 $8000 io! ;

: esc? ( -- ? ) key? if key 27 = else false then ;

\ -------------------------------------------------------------
\  Fixpoint output
\ -------------------------------------------------------------

: hold< ( c -- ) \ Add a character at the end of the number string
  hld @   dup 1- dup hld !    BUF hld @ -  move
  BUF 1- c!
;

: f# ( u -- u ) base @ um* .digit hold< ;

: f.n ( f n -- ) ( f-Low f-High n -- ) \ Prints a s15.16 number

  >r ( Low High R: n )

  dup 0< if [char] - emit then
  dabs
  ( uLow uHigh )
  0 <# #s   ( uLow 0 0 )
  drop swap ( 0 uLow )

  [char] , hold<
  r> 0 ?do f# loop

  #> type space
;

: f. ( f -- ) 8 cells f.n ;

\ -------------------------------------------------------------
\  Fixpoint calculations
\ -------------------------------------------------------------

: 2variable ( d -- ) create , , 0 foldable ;
\ : 2constant ( d -- ) create , , 0 foldable does> 2@ ;
: 2constant ( d -- ) swap : postpone literal postpone literal postpone ; 0 foldable ;

: s>f ( n -- f ) 0 swap ; 1 foldable  \ Signed integer --> Fixpoint s15.16
\ : f>s ( f -- n ) nip    ; 2 foldable  \ Fixpoint s15.16 --> Signed integer

: f* ( f1 f2 -- f )

        dup >r dabs
  2swap dup >r dabs

            ( d c b a )
  swap >r   ( d c a R: b )
  2dup *    ( d c a ac R: b )
  >r        ( d c a R: b ac )
  >r        ( d c R: b ac a )
  over      ( d c d R: b ac a )
  r> um*    ( d c L H R: b ac )
  r> +      ( d c L H' R: b )
  rot       ( d L H' c R: b )
  r@        ( d L H' c b R: b )
  um* d+    ( d L' H'' R: b )
  rot       ( L' H'' d R: b )
  r>        ( L' H'' d b )
  um* nip 0 ( L' H'' db 0 )
  d+        ( L'' H''' )

  r> r> xor 0< if dnegate then

; 4 foldable

0. 2variable dividend
0. 2variable shift
0. 2variable divisor

: (ud/mod) ( -- )

  16 cells
  begin

    \ Shift the long chain of four cells.

       dividend cell+ @ dup 8 cells 1- rshift >r 2*    dividend cell+ !
    r> dividend       @ dup 8 cells 1- rshift >r 2* or dividend       !
    r>    shift cell+ @ dup 8 cells 1- rshift >r 2* or    shift cell+ !
    r>    shift       @                          2* or    shift       !

    \ Subtract divisor when shifted out value is large enough

    shift 2@ divisor 2@  du>=

    if \ Greater or Equal: Subtract !
      shift 2@ divisor 2@ d- shift 2!
      dividend cell+ @ 1+ dividend cell+ !
    then

    1- dup 0=
  until
  drop
;

: ud/mod ( ud1 ud2 -- ud-rem ud-div )

     divisor 2!
  0. shift 2!
     dividend 2!

  (ud/mod)

  shift 2@
  dividend 2@

; 4 foldable

: f/ ( f1 f2 -- f )

  dup >r dabs  divisor 2!
  dup >r dabs  0 Shift 2! 0 swap dividend 2!

  (ud/mod)

  dividend 2@
  r> r> xor 0< if dnegate then

; 4 foldable

\ -------------------------------------------------------------
\  Double tools
\ -------------------------------------------------------------

: 2or  ( d1 d2 -- d ) >r swap >r or  r> r> or  ; 4 foldable
: 2and ( d1 d2 -- d ) >r swap >r and r> r> and ; 4 foldable
: 2xor ( d1 d2 -- d ) >r swap >r xor r> r> xor ; 4 foldable

: d0<   ( d -- ? ) nip 0< ; 2 foldable

: d= ( x0 x1 y0 y1 -- ? )

  swap ( x0 x1 y1 y0 )
  >r   ( x0 x1 y1 R: y0 )
  =    ( x0 x1=y1 R: y0 )
  swap ( x1=y1 x0 R: y0 )
  r>   ( x1=y1 x0 y0 )
  =    ( x1=y1 x0=y0 )
  and
; 4 foldable

: d<> d= not ; 4 foldable

: d2/  ( x1 x2 -- x1' x2' ) >r 1 rshift r@ 8 cells 1- lshift or r> 2/       ; 2 foldable
: dshr ( x1 x2 -- x1' x2' ) >r 1 rshift r@ 8 cells 1- lshift or r> 1 rshift ; 2 foldable

\ : 2lshift  ( ud u -- ud* ) begin dup while >r d2*  r> 1- repeat drop ; 3 foldable
\ : 2arshift (  d u --  d* ) begin dup while >r d2/  r> 1- repeat drop ; 3 foldable
\ : 2rshift  ( ud u -- ud* ) begin dup while >r dshr r> 1- repeat drop ; 3 foldable

: 2lshift ( low high u -- )
  dup >r ( low high u R: u )
  lshift ( low high* )
  over 8 cells r@ - rshift or
  over r@ 8 cells - lshift or
  swap r> lshift swap
; 3 foldable

: 2rshift ( low high u -- )
  >r swap ( high low R: u )
  r@ rshift
  over 8 cells r@ - lshift or
  over r@ 8 cells - rshift or
  swap
  r> rshift
; 3 foldable

: 2arshift ( low high u -- )
  dup >r 8 cells u< ( low high R: u )
  if
    swap ( high low R: u )
    r@ rshift
    over 8 cells r@ - lshift or
  else
    nip dup r@ 8 cells - arshift
  then
  swap r> arshift
; 3 foldable

: 2nip ( d1 d2 -- d2 )
  >r nip nip r>
; 4 foldable

: 2rot ( d1 d2 d3 -- d2 d3 d1 )
  >r >r ( d1 d2 R: d3 )
  2swap ( d2 d1 R: d3 )
  r> r> ( d2 d1 d3 )
  2swap ( d2 d3 d1 )
; 6 foldable

: d<            \ ( al ah bl bh -- flag )
    rot         \ al bl bh ah
    2dup =
    if
        2drop u<
    else
        > nip nip
    then
; 4 foldable

: d>  ( d1 d2 -- ? ) 2swap d< ; 4 foldable
: d>= ( d1 d2 -- ? ) d< not   ; 4 foldable
: d<= ( d1 d2 -- ? ) d> not   ; 4 foldable

: dmin ( d1 d2 -- d ) 2over 2over d< if 2drop else 2nip then ; 4 foldable
: dmax ( d1 d2 -- d ) 2over 2over d< if 2nip else 2drop then ; 4 foldable

: du<           \ ( al ah bl bh -- flag )
    rot         \ al bl bh ah
    2dup =
    if
        2drop u<
    else
        u> nip nip
    then
; 4 foldable

: du>  ( d1 d2 -- ? ) 2swap du< ; 4 foldable
: du>= ( d1 d2 -- ? ) du< not   ; 4 foldable
: du<= ( d1 d2 -- ? ) du> not   ; 4 foldable

\ #######   DUMP   ############################################

: dump
    ?dup
    if
        1- 4 rshift 1+
        0 do
            cr dup dup .x space space
            16 0 do
                dup c@ .x2 1+
            loop
            space swap
            16 0 do
                dup c@ dup bl 127 within invert if
                    drop [char] .
                then
                emit 1+
            loop
            drop
        loop
    then
    drop
;

\ #######   INSIGHT   #########################################


( Deep insight into stack, dictionary and code )
( Matthias Koch )

: .s ( -- )
  \ Save initial depth
  depth dup >r

  \ Flush stack contents to temporary storage
  begin
    dup
  while
    1-
    swap
    over cells pad + !
  repeat
  drop

  \ Print original depth
  ." [ "
  r@ .x2
  ." ] "

  \ Print all elements in reverse order
  r@
  begin
    dup
  while
    r@ over - cells pad + @ .x
    1-
  repeat
  drop

  \ Restore original stack
  0
  begin
    dup r@ u<
  while
    dup cells pad + @ swap
    1+
  repeat
  rdrop
  drop
;

: insight ( -- )  ( Long listing of everything inside of the dictionary structure )
    base @ hex cr
    forth @
    begin
        dup
    while
         ." Addr: "     dup .x
        ."  Link: "     dup link@ .x
        ."  Flags: "    dup cell+ c@ 128 and if ." I " else ." - " then
                        dup @ 7 and ?dup if 1- u. else ." - " then
        ."  Code: "     dup cell+ count 127 and + aligned .x
        space           dup cell+ count 127 and type
        link@ cr
    repeat
    drop
    base !
;

0 variable disasm-$    ( Current position for disassembling )
0 variable disasm-cont ( Continue up to this position )

: name. ( Address -- )  ( If the address is Code-Start of a dictionary word, it gets named. )

  dup ['] s, 24 + = \ Is this a string literal ?
  if
    ."   --> s" [char] " emit space
    disasm-$ @ count type
    [char] " emit

    disasm-$ @ c@ 1+ aligned disasm-$ +!
    drop exit
  then

  >r
  forth @
  begin
    dup
  while
    dup cell+ count 127 and + aligned ( Dictionary Codestart )
      r@ = if ."   --> " dup cell+ count 127 and type then
    link@
  repeat
  rdrop drop
;

: alu. ( Opcode -- ) ( If this opcode is from an one-opcode definition, it gets named. This way inlined ALUs get a proper description. )

  dup $6127 = if ." >r"    drop exit then
  dup $6B11 = if ." r@"    drop exit then
  dup $6B1D = if ." r>"    drop exit then
  dup $600C = if ." rdrop" drop exit then

  $FF73 and
  >r
  forth @
  begin
    dup
  while
    dup cell+ count 127 and + aligned @ ( Dictionary First-Opcode )
        dup $E080 and $6080 =
        if
          $FF73 and r@ = if rdrop cell+ count 127 and type space exit then
        else
          drop
        then

    link@
  repeat
  drop r> drop
;


: memstamp ( Addr -- ) dup .x ." : " @ .x ."   " ; ( Shows a memory location nicely )

: disasm-step ( -- )
  disasm-$ @ memstamp
  disasm-$ @ @        ( Fetch next opcode )
  1 cells disasm-$ +! ( Increment position )

  dup $8000 and         if ." Imm  " $7FFF and       dup .x 6 spaces                      .x       exit then ( Immediate )
  dup $E000 and $0000 = if ." Jmp  " $1FFF and cells dup                                  .x name. exit then ( Branch )
  dup $E000 and $2000 = if ." JZ   " $1FFF and cells disasm-cont @ over max disasm-cont ! .x       exit then ( 0-Branch )
  dup $E000 and $4000 = if ." Call " $1FFF and cells dup                                  .x name. exit then ( Call )
                           ." Alu"   13 spaces dup alu. $80 and if ." exit" then                             ( ALU )
;

: seec ( -- ) ( Continues to see )
  base @ hex cr
  0 disasm-cont !
  begin
    disasm-$ @ @
    dup  $E080 and $6080 =           ( Loop terminates with ret )
    swap $E000 and 0= or             ( or when an unconditional jump is reached. )
    disasm-$ @ disasm-cont @ u>= and ( Do not stop when there has been a conditional jump further )

    disasm-step cr
  until

  base !
;

: see ( -- ) ( Takes name of definition and shows its contents from beginning to first ret )
  ' disasm-$ !
  seec
;

cornerstone new

