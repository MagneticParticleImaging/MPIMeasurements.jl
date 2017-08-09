using MPIMeasurements
using Unitful

# Create Isel BaseScanner object
iR = iselRobot("/dev/ttyS0")
hS = Scanner{IselRobot}(scannerSymbols[3], iR, dSampleRegularScanner, ()->())
initRefZYX(hR)
################# Use case 1 Basic Move #######################################

# Move absolue LowLevel no safetyCheck!
movePark(hR)
moveCenter(hR)
getPos(hR)
moveAbs(hR, 1.0u"mm", 0.0u"mm", 0.0u"mm")

# Move absolute MidLevel
posXYZ = [1.0u"mm",0.0u"mm",0.0u"mm"]
moveAbs(hS, posXYZ)

################# Use case 2 Move and Measure #################################
