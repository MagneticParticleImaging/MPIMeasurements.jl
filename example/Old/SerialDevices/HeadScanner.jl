using MPIMeasurements
using Unitful

# Create Isel BaseScanner object
iR = IselRobot("/dev/ttyS0")

initRefZYX(iR)
################# Use case 1 Basic Move #######################################

# Move absolue LowLevel no safetyCheck!
movePark(iR)
moveCenter(iR)
getPos(iR)
moveAbs(iR, 1.0Unitful.mm, 0.0Unitful.mm, 0.0Unitful.mm)

# Move absolute MidLevel
posXYZ = [1.0Unitful.mm,0.0Unitful.mm,0.0Unitful.mm]
moveAbs(iR, posXYZ)

################# Use case 2 Move and Measure #################################
