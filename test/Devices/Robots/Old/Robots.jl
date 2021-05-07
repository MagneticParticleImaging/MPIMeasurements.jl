using MPIMeasurements
using Base.Test
using Unitful

dR = DummyRobot()
# bR = BrukerRobot("RobotServer")
# hR = IselRobot("/dev/ttyUSB0")
moveRel(dR, dSampleRegularScanner,[10.0Unitful.mm,0.0Unitful.mm,0.0Unitful.mm])
#moveAbs(dR, dSampleRegularScanner,[0.0Unitful.mm,0.0Unitful.mm,0.0Unitful.mm])
