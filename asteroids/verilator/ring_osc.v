
`default_nettype none

/* verilator lint_off UNUSEDPARAM */

module ring_osc ( input resetq, output osc_out );

  parameter NUM_LUTS = 42;

  assign osc_out = ~resetq;

endmodule

/* verilator lint_on UNUSEDPARAM */
