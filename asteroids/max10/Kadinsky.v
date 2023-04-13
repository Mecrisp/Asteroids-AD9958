
`default_nettype none

/* verilator lint_off WIDTH */

module Kadinsky(

  // Referenztakt von außen

  input  wire oscillator_10mhz,   // Einkommende Referenzfrequenz
  output wire DDS_Clk_out,        // Wird von der PLL im FPGA generiert und ausgegeben

  input  wire Sync_clk,           // Kommt von der DDS zurück

  // DDS

  output wire DDS_pw_dwn,

  output wire DDS_sclk,
  output wire DDS_cs,
  output wire DDS_io_update,
  output wire DDS_Reset,

  output wire [3:0] DDS_sdio,

  input wire [3:0] DDS_P,

  // Analoges

  output wire Ch0_enable,
  output wire Ch1_enable,

  // Terminal und LEDs

  output wire terminal_tx,
  input  wire terminal_rx,

  output wire led_running,
  output wire led_underflow

);

  // ######   Analoges   ######################################

  assign Ch0_enable = 1;
  assign Ch1_enable = 1;

  // ######   Taktkonfiguration   #############################

  // Reset-Signal für die DDS mit dem Rohtakt generieren
  // Die schaltet nämlich den Takt aus, wenn sie unter Reset steht.

  wire clock_in_locked;
  assign DDS_pw_dwn = 0;
  assign DDS_Reset  = ~clock_in_locked;

  Takt10zu100 pll10_ ( .inclk0(oscillator_10mhz), .c0(DDS_Clk_out), .locked(clock_in_locked) );

  // Takt, der von der DDS zurück kommt für den Rest des Systems verwenden

  wire clk = Sync_clk; // 25 MHz (Start) oder 100 MHz (fertig initialisiert) von der DDS zurück

  // ######   Rekonfiguration von Innen   #####################

  reg neustart = 0;

  wire rublock_antwort; // Brauchen wir hier nicht.

  fiftyfivenm_rublock _reconfiguration
  (
    .rconfig(neustart), // High-Pegel triggert die Rekonfiguration.

    .clk(clk),       // Takt für das Modul, sonst funktioniert es nicht
    .rsttimer(1),   // Watchdog-Timer soll beständig zurückgesetzt bleiben
    .shiftnld(0),  // Momentan sollen keine Daten rein- oder rausgeschoben werden.
    .captnupdt(0),
    .regin(0),
    .regout(rublock_antwort)
  );

  // ######   Reset logic   #####################################

  wire reset_button = clock_in_locked;

  reg [15:0] reset_cnt = 0;
  wire resetq_unbuffered = &reset_cnt;

  always @(posedge clk) begin
    if (reset_button) reset_cnt <= reset_cnt + !resetq_unbuffered;
    else              reset_cnt <= 0;
  end

  reg resetq = 0;
  always @(posedge clk) resetq <= resetq_unbuffered;

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
  //   Pixelpuffer
  // --------------------------------------------------------------------------

  reg [31:0] ch0frequenzoffset = 0;
  reg [31:0] ch1frequenzoffset = 0;

  // Großer Ringpuffer für die Grafikausgabe

  reg  [ (10 + 10 + 32 + 32)-1 : 0 ] pixelpuffer [255:0];

  reg  [7:0] pixellesezeiger = 0;
  reg  [7:0] pixelschreibzeiger = 0;

  wire [7:0] pixelschreibstelle = pixelschreibzeiger + 1;

  wire [31:0] ch0frequenz  = pixelpuffer[pixellesezeiger][31: 0] + ch0frequenzoffset;
  wire [31:0] ch1frequenz  = pixelpuffer[pixellesezeiger][63:32] + ch1frequenzoffset;

  wire  [9:0] ch0amplitude = pixelpuffer[pixellesezeiger][73:64];
  wire  [9:0] ch1amplitude = pixelpuffer[pixellesezeiger][83:74];

  wire pixelpufferleer =  pixelschreibzeiger == pixellesezeiger;
  wire pixelpuffervoll =  pixelschreibstelle == pixellesezeiger;

  reg underflow = 0;

  // Getakteter Teil

  always @(posedge clk)
  begin
    if (pixelschritt) // Die Grafik soll synchron zur DDS laufen !
    begin
      if (~pixelpufferleer) pixellesezeiger <= pixellesezeiger + 1;
    end // Divider für den Pixeltakt
  end

  assign led_running   = resetq & ~underflow; // Läuft gerade
  assign led_underflow = resetq &  underflow; // Unterlauf aufgetreten

  // ######   UART   ##########################################

  // Terminal über die Debug-Pinleiste:

  wire uart0_valid      /* verilator public_flat */;
  wire uart0_busy       /* verilator public_flat */;
  wire [7:0] uart0_data /* verilator public_flat */;
  wire uart0_wr         /* verilator public_flat */ = io_wr & io_addr[12];
  wire uart0_rd         /* verilator public_flat */ = io_rd & io_addr[12];

  buart #(
     .FREQ_MHZ(100),
     .BAUDS(115200)
  ) _uart0 (
     .clk(clk),
     .resetq(resetq),
     .rx(terminal_rx),
     .tx(terminal_tx),
     .rd(uart0_rd),
     .wr(uart0_wr),
     .valid(uart0_valid),
     .busy(uart0_busy),
     .tx_data(io_dout[7:0]),
     .rx_data(uart0_data));

  // ######   Bus    ############################################

  wire io_rd, io_wr;
  wire [15:0] io_addr;
  wire [15:0] io_dout /* verilator public_flat */ ;
  wire [15:0] io_din  /* verilator public_flat */ ;

  reg interrupt = 0;

  // ######   PROCESSOR   #####################################

  j1 _j1(
    .clk(clk),
    .resetq(resetq),

    .io_rd(io_rd),
    .io_wr(io_wr),
    .io_dout(io_dout),
    .io_din(io_din),
    .io_addr(io_addr),

    .interrupt_request(interrupt)
  );

  // ######   TICKS   #########################################

  reg [15:0] ticks;

  wire [16:0] ticks_plus_1 = ticks + 1;

  always @(posedge clk)
    if (io_wr & io_addr[14])
      ticks <= io_dout;
    else
      ticks <= ticks_plus_1;

  always @(posedge clk) // Generate interrupt on ticks overflow
    interrupt <= ticks_plus_1[16];

  // ######   RING OSCILLATOR   ###############################

  wire random;
  ring_osc #(.NUM_LUTS(1)) chaoskern (.resetq(resetq), .osc_out(random));

  // ######   IO PORTS   ######################################

  /*        bit READ            WRITE

      ---------------------------------------------------------
      0001  0
      0002  1
      0004  2
      0008  3
      ---------------------------------------------------------
      0010  4
      0020  5
      0040  6
      0080  7
      ---------------------------------------------------------
      0100  8
      0200  9   Frequenzoffset  Frequenzoffset
      0400  10  Status          Pixel-FIFO
      0800  11
      ---------------------------------------------------------
      1000  12  UART RX         UART TX
      2000  13  UART Flags
      4000  14  Ticks           Set Ticks
      8000  15                  Reset
      ---------------------------------------------------------
  */

  assign io_din =

    // Konfiguration des Frequenzoffsets

    (io_addr[ 9] & (io_addr[7:4] ==  2) ?  ch0frequenzoffset[15:0]                  : 16'd0) |
    (io_addr[ 9] & (io_addr[7:4] ==  3) ?  ch0frequenzoffset[31:16]                 : 16'd0) |
    (io_addr[ 9] & (io_addr[7:4] ==  4) ?  ch1frequenzoffset[15:0]                  : 16'd0) |
    (io_addr[ 9] & (io_addr[7:4] ==  5) ?  ch1frequenzoffset[31:16]                 : 16'd0) |

    // Status des Pixel-FIFOs

    (io_addr[10] & (io_addr[7:4] ==  9) ?  {13'b0, underflow, pixelpufferleer, pixelpuffervoll}   : 16'd0) |

    // Status des zweiten Updatepulses

    (io_addr[10] & (io_addr[7:4] == 10) ?  zweites_update                                         : 16'd0) |

    // Infrastruktur drumherum

    (io_addr[12] ? { 8'd0, uart0_data}                                              : 16'd0) |
    (io_addr[13] ? {13'd0,                        random, uart0_valid, !uart0_busy} : 16'd0) |
    (io_addr[14] ?         ticks                                                    : 16'd0) ;


  reg [15:0] new_freq0low, new_freq0high, new_freq1low, new_freq1high;
  reg  [9:0] new_amplitude0;

  always @(posedge clk) begin

    // Konfiguration des Frequenzoffsets

    if (io_wr & io_addr[ 9] & (io_addr[7:4] ==  2))  ch0frequenzoffset[15:0]  <= io_dout;
    if (io_wr & io_addr[ 9] & (io_addr[7:4] ==  3))  ch0frequenzoffset[31:16] <= io_dout;
    if (io_wr & io_addr[ 9] & (io_addr[7:4] ==  4))  ch1frequenzoffset[15:0]  <= io_dout;
    if (io_wr & io_addr[ 9] & (io_addr[7:4] ==  5))  ch1frequenzoffset[31:16] <= io_dout;

    // Register zum Hinzufügen neuer Pixel zum Pixel-FIFO

    if (io_wr & io_addr[10] & (io_addr[7:4] ==  3))  new_freq0low   <= io_dout; // Freq 0 low
    if (io_wr & io_addr[10] & (io_addr[7:4] ==  4))  new_freq0high  <= io_dout; // Freq 0 high
    if (io_wr & io_addr[10] & (io_addr[7:4] ==  5))  new_freq1low   <= io_dout; // Freq 1 low
    if (io_wr & io_addr[10] & (io_addr[7:4] ==  6))  new_freq1high  <= io_dout; // Freq 1 high
    if (io_wr & io_addr[10] & (io_addr[7:4] ==  7))  new_amplitude0 <= io_dout; // Amplitude 0

    if (io_wr & io_addr[10] & (io_addr[7:4] ==  8))  begin
                                                       pixelpuffer[pixelschreibstelle][ 15:0] <= new_freq0low;
                                                       pixelpuffer[pixelschreibstelle][31:16] <= new_freq0high;
                                                       pixelpuffer[pixelschreibstelle][47:32] <= new_freq1low;
                                                       pixelpuffer[pixelschreibstelle][63:48] <= new_freq1high;
                                                       pixelpuffer[pixelschreibstelle][73:64] <= new_amplitude0;
                                                       pixelpuffer[pixelschreibstelle][83:74] <= io_dout; // Amplitude 1
                                                       pixelschreibzeiger <= pixelschreibstelle;
                                                     end
    // Status des Pixel-FIFOs:

    if (io_wr & io_addr[10] & (io_addr[7:4] ==  9)) begin
                                                      underflow <= 0;
                                                    end
                                                    else
                                                    begin
                                                      underflow <= underflow | pixelschritt & pixelpufferleer;
                                                    end

    if (io_wr & io_addr[10] & (io_addr[7:4] == 10)) zweites_update <= io_dout;

    // Infrastruktur drumherum

    if (io_wr & io_addr[15]) neustart <= io_dout;

  end

endmodule

