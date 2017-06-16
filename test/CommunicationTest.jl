using SerialPorts

serialports = list_serialports()
s = SerialPort("/dev/ttyACM1", 250000)
write(s, "Hello World!\n")
close(s)
