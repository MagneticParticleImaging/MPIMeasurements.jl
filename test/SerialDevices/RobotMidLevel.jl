using MPIMeasurements
using Base.Test
using Unitful

bR = brukerRobot("RobotServer")
bS = BrukerScanner{BrukerRobot}(:BrukerScanner, bR, dSampleRegularScanner, ()->())

# hR = iselRobot("/dev/ttyS0")
# hS = HeadScanner{IselRobot}(:HeadScanner, hR, dSampRegualrScanner, ()->())
