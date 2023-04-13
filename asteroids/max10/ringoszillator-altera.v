
// Nur ein Wrapper, damit Quartus das annimmt.

module delaybuffer (input in, output out);
  LCELL delaybuffer_inst (
        .in  ( in ),
        .out ( out )
  );
endmodule

module ring_osc ( input resetq, output osc_out );

  parameter NUM_LUTS = 42;

  wire [NUM_LUTS:0] buffers_in, buffers_out;
  assign buffers_in = {buffers_out[NUM_LUTS - 1:0], chain_in};
  wire chain_out = buffers_out[NUM_LUTS];
  wire chain_in = resetq ? !chain_out : 0;

  delaybuffer buffers_inst [NUM_LUTS:0] (
        .in  ( buffers_in ),
        .out ( buffers_out )
  );

  assign osc_out = chain_out;

endmodule
