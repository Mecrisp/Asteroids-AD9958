reset
set encoding utf8
set terminal png enhanced size 800, 800
set xrange [69:81]
set yrange [69:81]
set output "frame-00000000.dat.png"
plot "frame-00000000.dat" u ($3 * 400/2**32):($4 * 400/2**32) w lp pt 7 ps 0.8 notitle
