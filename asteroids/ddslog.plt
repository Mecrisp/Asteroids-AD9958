reset
set encoding utf8
set terminal png enhanced size 1200, 800
set xrange [69:81]
set xrange [69:81]
set output "ddslog.png"
plot "ddslog.txt" u ($5 * 400/2**32 + 0.001 * $0):($6 * 400/2**32 + 0.001 * $0):($7+$8) w p pt 7 ps 0.8 palette
