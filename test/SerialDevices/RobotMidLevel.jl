using MPIMeasurements
using Base.Test
using Unitful

bR = brukerRobot("RobotServer")
bS = BrukerScanner{BrukerRobot}(:BrukerScanner, bR, dSampleRegularScanner, ()->())

# hR = headRobot("/dev/ttyS0")
# hS = HeadScanner{HeadRobot}(:HeadScanner, hR, dSampRegualrScanner, ()->())
