
reset
set encoding utf8
set terminal png enhanced size 800, 800
set xrange [69:81]
set yrange [0:1050]
set output "Amplitude-00000000.dat.png"

set key bottom right

plot "frame-00000000.dat" u ($3 * 400/2**32):5 w lp pt 7 ps 0.8 title "Amplitude X", "frame-00000000.dat" u ($4 * 400/2**32):6 w lp pt 7 ps 0.8 title "Amplitude Y", 1023 title "Maximum"
