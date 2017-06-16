using SerialPorts

serialports = list_serialports()
s = SerialPort("/dev/ttyS0", 19200)
#baurate 19200, 8 Datenbit, 1 Stoppbit, keine Parität
r1=write(s, "@07\r")
r2=write(s, "@0R7\r")
#close(s)
