`timescale 1ns/100ps  // 1 ns time unit, 100 ps resolution
`default_nettype none // Makes it easier to detect typos !

module test_dds;
    reg clk;
    always #5.0 clk = !clk;

    reg resetq = 0;


   Kadinsky _DDS(

   .Sync_clk(clk)

);

   /***************************************************************************/
   // Test sequence
   /***************************************************************************/

   integer i;
   initial begin
     $dumpfile("dds.vcd");    // create a VCD waveform dump
     $dumpvars(0, test_dds); // dump variable changes in the testbench
                              // and all modules under it

     clk = 0;
     resetq = 0;
     @(negedge clk);
     resetq = 1;

     for (i = 0; i < 1000; i = i + 1) begin
       @(negedge clk);
     end



     $finish();
   end
endmodule
