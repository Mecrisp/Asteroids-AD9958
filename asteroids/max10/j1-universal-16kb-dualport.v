
`default_nettype none

// `include "../common-verilog/stack2.v"
// `include "../common-verilog/stack3.v"

module j1(
  input wire clk,
  input wire resetq,

  output wire io_rd,
  output wire io_wr,
  output wire [15:0] io_addr,
  output wire [15:0] io_dout,
  input  wire [15:0] io_din,

  input  wire interrupt_request
);

  parameter MEMWORDS = 8192;       // Maximum of 8k words of 16 bits = 16 kb.
  parameter IRQOPCODE = 16'h4001; // Interrupt: Execute "Call 0002".

  // ######   MEMORY   ########################################

    wire mem_wr;
    wire [12:0] code_addr;
    reg  [15:0] insn_from_memory;
    reg  [15:0] fetch_from_memory;

    reg [15:0] mem [0:MEMWORDS-1]; initial $readmemh("iceimage.hex", mem);

    always @(posedge clk) begin
        insn_from_memory  <= mem[code_addr];
        if (mem_wr) mem[io_addr[13:1]] <= io_dout;
        else fetch_from_memory <= mem[st0N[13:1]];
    end

  // ######   PROCESSOR   #####################################

  reg [4:0] rsp, rspN;          // Return stack pointer
  reg [4:0] dsp, dspN;          // Data stack pointer
  reg [15:0] st0, st0N;         // Top of data stack
  reg dstkW;                    // Data stack write

  reg [15:0] pc, pcN;           // Program Counter. pc[0] is interrupt enable bit.

  wire interrupt_enable = pc[0];
  wire interrupt = interrupt_request & interrupt_enable;

  wire [15:0] insn = interrupt ? IRQOPCODE : insn_from_memory;  // Interrupt: Execute "Call 3FFE".
  wire [15:0] pc_plus_2 = (pc + {14'b0, ~interrupt, 1'b0}) | {interrupt, 15'b0};      // Do not increment PC for interrupts to continue later at the same location. Set MSB on interrupt entries which will be pushed to return stack !

  reg rstkW;                    // Return stack write
  wire [15:0] rstkD;            // Return stack write value
  reg notreboot = 0;

  assign io_addr = st0[15:0];
  assign code_addr = pcN[13:1];

  // The D and R stacks
  wire [15:0] st2, st1, rst0;
  reg [1:0] dspI, rspI;

  stack2 #(.DEPTH(32)) rstack(.clk(clk), .rd(rst0), .we(rstkW), .wd(rstkD), .delta(rspI));
  stack3 #(.DEPTH(32)) dstack(.clk(clk), .rd1(st1), .we(dstkW), .wd(st0),   .delta(dspI), .rd2(st2)); // This one supports 2drop

  wire [16:0] minus = {1'b1, ~st0} + st1 + 1;

  wire signedless = st0[15] ^ st1[15] ? st1[15] : minus[16];
  wire unsignedless = minus[16];
  wire zeroflag = minus[15:0] == 0;

  wire [31:0] umstar = st0 * st1;

  always @*
  begin
    // Compute the new value of st0
    casez (insn[15:8])

  //  8'b011_00000: st0N = st0;                                   // TOS
      8'b011_00001: st0N = st1;                                   // NOS
      8'b011_00010: st0N = st0 + st1;                             // +
      8'b011_00011: st0N = st0 & st1;                             // and

      8'b011_00100: st0N = st0 | st1;                             // or
      8'b011_00101: st0N = st0 ^ st1;                             // xor
      8'b011_00110: st0N = ~st0;                                  // invert
      8'b011_00111: st0N = {16{zeroflag}};                        //  =

      8'b011_01000: st0N = {16{signedless}};                      //  <
      8'b011_01001: st0N = {st0[15], st0[15:1]};                  // 1 arshift
      8'b011_01010: st0N = {st0[14:0], 1'b0};                     // 1 lshift
      8'b011_01011: st0N = rst0;                                  // r@

      8'b011_01100: st0N = minus[15:0];                           // -
      8'b011_01101: st0N = io_din;                                // Read IO
      8'b011_01110: st0N = {11'b0, dsp};                          // depth
      8'b011_01111: st0N = {16{unsignedless}};                    // u<

  //  8'b000_?????: st0N = st0;                                   // Jump
  //  8'b010_?????: st0N = st0;                                   // Call
      8'b001_?????: st0N = st1;                                   // Conditional jump

      8'b1??_?????: st0N = { 1'b0, insn[14:0] };                  // Literal

  // Specls available on HX8K:

      8'b011_10000: st0N = st1 << st0;                            // lshift
      8'b011_10001: st0N = st1 >> st0;                            // rshift
      8'b011_10010: st0N = $signed(st1) >>> st0;                  // arshift
      8'b011_10011: st0N = {11'b0, rsp};                          // rdepth

      8'b011_10100: st0N = umstar[15:0];                          // Low  um*
      8'b011_10101: st0N = umstar[31:16];                         // High um*
      8'b011_10110: st0N = st0 + 1;                               // 1+
      8'b011_10111: st0N = st0 - 1;                               // 1-

      8'b011_11000: st0N = st2;                                   // 3OS
      8'b011_11001: st0N = fetch_from_memory;                     // @

      default: st0N = st0;
    endcase
  end

  wire func_T_N =   (insn[6:4] == 1);
  wire func_T_R =   (insn[6:4] == 2);
  wire func_write = (insn[6:4] == 3);
  wire func_iow =   (insn[6:4] == 4);
  wire func_ior =   (insn[6:4] == 5);
  wire func_dint =  (insn[6:4] == 6);
  wire func_eint =  (insn[6:4] == 7);

  wire is_alu = notreboot & (insn[15:13] == 3'b011);

  assign mem_wr = is_alu & func_write;
  assign io_wr  = is_alu & func_iow;
  assign io_rd  = is_alu & func_ior;
  assign io_dout   = st1;

  wire eint = is_alu & func_eint;
  wire dint = is_alu & func_dint;

  wire interrupt_enableN =                   (interrupt_enable | eint) & ~(dint | interrupt); // Disable interrups on IRQ entry.
  wire interrupt_enableN_return = (rst0[15] | interrupt_enable | eint) & ~(dint | interrupt); // Reenable interrupts on return stack MSB.

  // Value which could be written to return stack: Either return address in case of a call or TOS.
  assign rstkD = (insn[13] == 1'b0) ? pc_plus_2 : st0;

  always @*
  begin
    casez (insn[15:13])                                  // Calculate new data stack pointer
    3'b1??:     {dstkW, dspI} = {1'b1,      2'b01};          // Literal
    3'b001:     {dstkW, dspI} = {1'b0,      2'b11};          // Conditional jump
    3'b011:     {dstkW, dspI} = {func_T_N,  {insn[1:0]}};    // ALU
    default:    {dstkW, dspI} = {1'b0,      2'b00};          // Default: Unchanged
    endcase
    dspN = dsp + {dspI[1], dspI[1], dspI[1], dspI};

    casez (insn[15:13])                                  // Calculate new return stack pointer
    3'b010:     {rstkW, rspI} = {1'b1,      2'b01};          // Call
    3'b011:     {rstkW, rspI} = {func_T_R,  insn[3:2]};      // ALU
    default:    {rstkW, rspI} = {1'b0,      2'b00};          // Default: Unchanged
    endcase
    rspN = rsp + {rspI[1], rspI[1], rspI[1], rspI};

    casez ({notreboot, insn[15:13], insn[7], |st0})      // New address for PC
    6'b0_???_?_?:   pcN = 0;                                     // Boot: Start at address zero with interrupts disabled
    6'b1_000_?_?,
    6'b1_010_?_?,
    6'b1_001_?_0:   pcN = {2'b0, insn[12:0], interrupt_enableN}; // Jumps & Calls: Destination address
    6'b1_011_1_?:   pcN = {1'b0, rst0[14:1], interrupt_enableN_return}; // ALU+exit: Return. Maybe reenable interrupts.
    default:        pcN = { pc_plus_2[15:1], interrupt_enableN}; // Default: Increment PC to next opcode
    endcase
  end

  always @(negedge resetq or posedge clk)
  begin
    if (!resetq) begin
      notreboot <= 0;
      { pc, dsp, rsp, st0 } <= 0;
    end else begin
      notreboot <= 1;
      { pc, dsp, rsp, st0 }  <= { pcN, dspN, rspN, st0N };
    end
  end

endmodule
