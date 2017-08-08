using MPIMeasurements
using Unitful

hr = iselRobot("/dev/ttyS0")
initRefZYX(hr)
moveRel(hr,10.0u"mm", 30, 20.0u"mm", 10000, 30.0u"mm", 40000)
# Basic Test
# using LibSerialPort
# #using SerialPorts
#
#
# #serialports = list_ports()
# #s = SerialPort("/dev/ttyS0", 19200)
# s = open("/dev/ttyS0", 19200)
# #baurate 19200, 8 Datenbit, 1 Stoppbit, keine Parität
#
# # r1=write(s, "@07\r")
# # r2=write(s, "@0R7\r")
# initCmds = initRefZYX()
# for cmd in initCmds
#   r = write(s, cmd)
#   sleep(0.1)
# end
#
# #close(s)
