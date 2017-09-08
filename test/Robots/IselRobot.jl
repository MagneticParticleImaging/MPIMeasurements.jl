using MPIMeasurements
using Unitful

hr = IselRobot("/dev/ttyS0")
initRefZYX(hr)
moveRel(hr,10.0u"mm", 5000, 20.0u"mm", 5000, 30.0u"mm", 5000)
# Basic Test
# using LibSerialPort
# serialports = list_ports()
# s = open("/dev/ttyS0", 19200)
# baurate 19200, 8 Datenbit, 1 Stoppbit, keine Parität
# r1=write(s, "@07\r")
# r2=write(s, "@0R7\r")
# close(s)
