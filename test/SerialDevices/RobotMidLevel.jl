using MPIMeasurements
using Base.Test
using Unitful

bR = brukerRobot("RobotServer")
bS = Scanner{BrukerRobot}(scannerSymbols[1], bR, dSampleRegularScanner, ()->())

# hR = iselRobot("/dev/ttyS0")
# hS = Scanner{IselRobot}(scannerSymbols[3], hR, dSampRegualrScanner, ()->())
