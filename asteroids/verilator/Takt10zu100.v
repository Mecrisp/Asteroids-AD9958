
`default_nettype none

module Takt10zu100(
  input  wire inclk0,
  output wire locked,
  output wire c0
  );

  assign c0 = inclk0;
  assign locked = 1'b1;

endmodule
