
#include <stdio.h>
#include "VKadinsky.h"
#include "verilated_vcd_c.h"
#include "VKadinsky___024root.h"

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    VKadinsky* Kadinsky = new VKadinsky;
    int i;

  // Log der Befehle an die DDS

  FILE *fdds;

  fdds=fopen("ddslog.txt", "w");
  if(fdds == NULL) exit(-1);
  int dds_sclk_state = 0;
  int dds_io_update_state = 0;
  int dds_bitcount = 0;
  int dds_data = 0;

  int dds_bytecount = 0;
  int dds_complete[22] =  { 0 };

  // Komplettes Grafik-Log

  FILE *fp;

  fp=fopen("grafiklog.txt", "w");
  if(fp == NULL) exit(-1);
  fprintf(fp, "Pixel clock cycle : f_ch0, f_ch1, a_ch0, a_ch1\n\n");

  // Log nach Frames sortiert

  int amplitude_old = 0;
  int pixelclock = 0;
  int framewechsel = 0;

  FILE *framep;
  char filename[256];

  sprintf(filename, "frame-%08d.dat", pixelclock);
  framep=fopen(filename, "w");
  if(framep == NULL) exit(-1);
  fprintf(framep, "Pixel clock cycle : f_ch0, f_ch1, a_ch0, a_ch1\n\n");

  // Emulation der Logik

    int data = 0;

    for (i = 0; ; i++) {

      Kadinsky->rootp->v__DOT__uart0_data = data;

      // Kommunikations-Flags

      Kadinsky->rootp->v__DOT__uart0_valid = 1;   // pretend to always have a character waiting
      Kadinsky->rootp->v__DOT__uart0_busy  = 0;   // pretend to never be busy

      // Taktgeber

      Kadinsky->Sync_clk = 1;
      Kadinsky->eval();
      Kadinsky->Sync_clk = 0;
      Kadinsky->eval();

      // Abgreifen des Terminals, ohne die tatsächliche Kommunikationslogik zu betrachten

      if (Kadinsky->rootp->v__DOT__uart0_wr) {
        putchar(Kadinsky->rootp->v__DOT__io_dout & 0xFF);
      }

      if (Kadinsky->rootp->v__DOT__uart0_rd) {
        data=getchar();
        // if (data ==  27) break;
        if (data == EOF) break;
        if (data == 127) { data=8; } // Replace DEL with Backspace
      }

      // DDS nimmt Bits bei steigender Flanke mit MSB zuerst entgegen:

      if ((dds_sclk_state == 0) && (Kadinsky->DDS_sclk == 1))
      {

        dds_data = (dds_data << 4) | Kadinsky->DDS_sdio;
        dds_bitcount += 1;
        if (dds_bitcount == 2)

        {
          // Die Roh-DDS-Daten mitschreiben, fürs Debuggen, solange die Zahl der Bytes vielleicht noch verkehrt ist:
          // fprintf (fdds, " %02X", dds_data);

          // Die Werte aus der DDS im Array sichern.
          dds_complete[dds_bytecount] = dds_data;
          if (dds_bytecount < 21 ) dds_bytecount++;

          dds_bitcount = 0;
          dds_data = 0;
        }

      }
      dds_sclk_state = Kadinsky->DDS_sclk;


      if ((dds_io_update_state == 0) && (Kadinsky->DDS_io_update == 1))
      {

        // Zum Zeitpunkt des Updates sollen die rausgeschobenen und im Array gesammelten Werte anzeigt werden:

        unsigned int ch1frequenz = dds_complete[ 3] << 24 | dds_complete[ 4] << 16 | dds_complete[ 5] << 8 | dds_complete[ 6];
        unsigned int ch2frequenz = dds_complete[14] << 24 | dds_complete[15] << 16 | dds_complete[16] << 8 | dds_complete[17];

        unsigned int ch1amplitude = (dds_complete[ 9] & 3) << 8 | dds_complete[10];
        unsigned int ch2amplitude = (dds_complete[20] & 3) << 8 | dds_complete[21];

        if (!( (ch1frequenz == 0) && (ch2frequenz == 0) && (ch1amplitude == 0) && (ch2amplitude == 0) ))
        {

        fprintf (fdds, "\n%010u : %010u : %10u %10u %3u %3u [", i, pixelclock, ch1frequenz, ch2frequenz, ch1amplitude, ch2amplitude);
        for (int k = 0; k < 22; k++) fprintf (fdds, " %02X", dds_complete[k]);
        fprintf (fdds, " ]");

        // Die Kurzfassung der wesentlichen Daten zum Zeichnen in die einzelnen Frame-Dateien ausgeben:
        fprintf (fp, "%u : %u %u %u %u \n", pixelclock, ch1frequenz, ch2frequenz, ch1amplitude, ch2amplitude);
    fprintf (framep, "%u : %u %u %u %u \n", pixelclock, ch1frequenz, ch2frequenz, ch1amplitude, ch2amplitude);

        }

        // Beim Wechsel von 1 zu 0 in der Resetleitung der Vektorgrafikeinheit, also auf fallender Flanke, beim nächsten Pixel ein neues Frame beginnen.

        if ( (ch1amplitude == 0) && (ch2amplitude==0) && (amplitude_old != 0) )
        {
          fclose(framep);
          // Neue Datei anlegen
          sprintf(filename, "frame-%08d.dat", pixelclock);
          framep=fopen(filename, "w");
          if(framep == NULL) exit(-1);
          fprintf(framep, "Pixel clock cycle : f_ch0, f_ch1, a_ch0, a_ch1\n\n");
      fprintf (framep, "%u : %u %u %u %u \n", pixelclock, ch1frequenz, ch2frequenz, ch1amplitude, ch2amplitude); // Idle-Pixel nochmal ausgeben
        }

        amplitude_old = ch1amplitude;

        // Die Roh-DDS-Daten mitschreiben, fürs Debuggen, solange die Zahl der Bytes vielleicht noch verkehrt ist:
        // fprintf (fdds, "\n%012u : %012u : --", i, pixelclock);

        dds_bytecount = 0;
        pixelclock++;
      }
      dds_io_update_state = Kadinsky->DDS_io_update;

    }

    printf("Simulation ended after %d cycles\n", i);
    delete Kadinsky;

    fclose(framep);
    fclose(fp);
    fclose(fdds);

    exit(0);
}
