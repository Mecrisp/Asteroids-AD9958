
`default_nettype none

/* verilator lint_off WIDTH */

module Kadinsky(

  input  wire Sync_clk,           // Kommt von der DDS zurück

  // DDS

  output wire DDS_pw_dwn,

  output wire DDS_sclk,
  output wire DDS_cs,
  output wire DDS_io_update,
  output wire DDS_Reset,

  output wire [3:0] DDS_sdio,

  input wire [3:0] DDS_P

);



  // ######   Taktkonfiguration   #############################

  // Reset-Signal für die DDS mit dem Rohtakt generieren
  // Die schaltet nämlich den Takt aus, wenn sie unter Reset steht.

  reg [22:0] dds_reset_cnt = 0;
  wire dds_resetq = &dds_reset_cnt;
  always @(posedge Sync_clk) dds_reset_cnt <= dds_reset_cnt + !dds_resetq;

  assign DDS_pw_dwn = 0;
  assign DDS_Reset = ~dds_resetq;

  // Takt, der von der DDS zurück kommt für den Rest des Systems verwenden

  wire clk = Sync_clk; // 25 MHz (Start) oder 100 MHz (fertig initialisiert) von der DDS zurück

  // ######   Reset logic   #####################################

  wire reset_button = 1; // Dieses Board hat keinen Resetknopf.

  reg [7:0] reset_cnt = 0;
  wire resetq = &reset_cnt;

  always @(posedge clk) begin
    if (reset_button) reset_cnt <= reset_cnt + !resetq;
    else              reset_cnt <= 0;
  end

  // ######   DDS-Konfiguration   #############################

  // Beim ersten Anlauf erstmal die DDS konfigurieren.

  reg  [175:0] dds_shift_register = { // Die erste Füllung initialisiert die DDS, 6 Bytes werden rausgeschrieben, also 48 Bits.
  // 22*8-1:0                     //  FR1          PLL * 4      Default      Default
                                      8'b00000001, 8'b10010011, 8'b00000000, 8'b00000000,

                                  //  CSR          Ch 0 & 1
                                      8'b00000000, 8'b11000000,

                                  //  CFR          Default 0    Default 3    Default 2 + Matched Delays
                                      8'b00000011, 8'b00000000, 8'b00000011, 8'b00100000,

                                  //  CSR          4-Bit
                                      8'b00000000, 8'b00000110,

                                  //  Padding, wird nicht rausgeschoben
                                      80'h0
                                    };

  // Später die Frequenz- und Amplitudenregister aktualisieren. Dafür werden insgesamt 22 Bytes gebraucht.

                                 //  CSR          CH 0 / 1     Frequency    f 31-24      f 23-16      f 15-8       f 7-0        Amplitude                          ..    ........
  wire [175:0] dds_neuer_befehl   = {8'b00000000, 8'b01000110, 8'b00000100, ch0frequenz,                                        8'b00000110, 8'b00000000, 6'b000100, ch0amplitude,
                                     8'b00000000, 8'b10000110, 8'b00000100, ch1frequenz,                                        8'b00000110, 8'b00000000, 6'b000100, ch1amplitude};

  reg [8:0] dds_bit_counter = 0;
  reg four_bit_mode = 0;

  reg [7:0] zweites_update = 0;

  // Während des Resets und um den Bitbreiten-Wechsel herum /CS high setzen
  // IO-Update ist jeweils für zwei SCLK-Zyklen aktiv; die DDS reagiert aber nur auf die steigende Flanke.

  assign DDS_cs        =                                                                                ~resetq | (~four_bit_mode & (dds_bit_counter > (8 * 12 * 2)));
  assign DDS_io_update = (dds_bit_counter[8:1] == 0) | four_bit_mode & (dds_bit_counter[8:1] == zweites_update) | (~four_bit_mode & (dds_bit_counter[8:1] == 96+2));

  // Vordersten vier Bit aus dem Schieberegister an die DDS anlegen.

  assign DDS_sdio[3] = four_bit_mode ? dds_shift_register[175] : 1'b0;
  assign DDS_sdio[2] = four_bit_mode ? dds_shift_register[174] : 1'b0;
  assign DDS_sdio[1] = four_bit_mode ? dds_shift_register[173] : 1'b0;
  assign DDS_sdio[0] = four_bit_mode ? dds_shift_register[172] : dds_shift_register[175];

  assign DDS_sclk      = dds_bit_counter[0] & ~DDS_cs; // Die Taktleitung laufe mit 50 MHz während /CS low = aktiv ist.

  // Neufüllen des Schieberegisters, wenn das letzte Bit rausgeschoben worden ist.
  wire shift_reload = four_bit_mode ? dds_bit_counter == (2 * 22 * 2 - 1) : dds_bit_counter == (8 * 22 * 2 - 1) ;

  // Wenn der Schieberegister frisch geladen ist, soll die Grafikeinheit einen Weiterspringen.
  // So haben die Multiplizierer viel Zeit, die Pixeldaten zum Laden in die DDS zu skalieren.

  wire pixelschritt = dds_bit_counter == 0;

  always @(posedge clk)
  begin
    if (~resetq)
    begin
      // Während des Resets soll der Counter bei 0 bleiben. Damit ruht auch DDS_sclk.
      dds_bit_counter <= 0;
      // Noch ist die DDS frisch aus dem Reset im 1-Bit-Modus.
      four_bit_mode <= 0;
    end
    else
    begin
      // Bits hochzählen, und am Ende zurückspringen.
      dds_bit_counter <= shift_reload ? 0 : dds_bit_counter + 1 ;

      // DDS nimmt Daten auf der steigenden Flanke entgegen.
      // Wenn SCLK gerade High ist, also die negative Flanke bevorsteht, den Schieberegister weiterlaufen lassen.
      if (dds_bit_counter[0]) dds_shift_register <= shift_reload ? dds_neuer_befehl :
                                                   four_bit_mode ? {dds_shift_register[171:0], 4'b0000} :
                                                                   {dds_shift_register[174:0], 1'b0};

      // Nach dem ersten Neuladen ist die PLL im 4-Bit-Modus.
      if (shift_reload) four_bit_mode <= 1;
    end
  end

  // --------------------------------------------------------------------------
  //   Vektorgrafikeinheit
  // --------------------------------------------------------------------------

  wire  [9:0] ch0amplitude      = 10'd1023; // a << 1;
  wire  [9:0] ch1amplitude      = 10'd255; // a << 1;

  wire [31:0] ch0frequenz = 32'hABCD1234;
  wire [31:0] ch1frequenz = 32'hFEFE5A5A;

endmodule

