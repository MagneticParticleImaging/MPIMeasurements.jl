using MPIMeasurements
using Base.Test
using Unitful

dR = DummyRobot()
# bR = BrukerRobot("RobotServer")
# hR = IselRobot("/dev/ttyUSB0")
moveRel(dR, dSampleRegularScanner,[10.0u"mm",0.0u"mm",0.0u"mm"])
#moveAbs(dR, dSampleRegularScanner,[0.0u"mm",0.0u"mm",0.0u"mm"])
