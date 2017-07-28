using MPIMeasurements
using Unitful

# Create Bruker Scanner object
bR = brukerRobot("RobotServer")
bS = BrukerScanner{BrukerRobot}(:BrukerScanner, bR, dSampleRegularScanner, ()->())

################# Use case 1 Basic Move #######################################

# Move absolue LowLevel no safetyCheck!
movePark(bR)
moveCenter(bR)
getPos(bR)
moveAbs(bR, 1.0u"mm", 0.0u"mm", 0.0u"mm")

# Move absolute MidLevel
posXYZ = [1.0u"mm",0.0u"mm",0.0u"mm"]
moveAbs(bS, posXYZ)

################# Use case 2 Move and Measure #################################
