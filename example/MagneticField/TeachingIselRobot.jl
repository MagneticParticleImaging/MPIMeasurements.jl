using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# Do NOT call this as a script, use commands manual in console each at a time
# Init robot
configFile="HeadScanner.toml"
scanner = MPIScanner(configFile)
robot = getRobot(scanner)

# Reference robot und move to old teaching position
initRefZYX(robot)
moveAbs(robot,0.0u"mm",0.0u"mm",0.0u"mm")

# check if you at the right position
currentPos = getPos(robot,u"mm")
println(currentPos)
println(robot.defCenterPos)

# use moveAbs command to navigate to desired new teaching position
moveAbs(robot,robot.defCenterPos[1]+ 1.0u"mm",robot.defCenterPos[2],robot.defCenterPos[3])
# or use moveRel
# moveRel(robot,1.0u"mm,0.0u"mm",0.0u"mm")
#
#
#...a few times moving manually with moveAbs or moveRel...
#
# if you have moved to your final new teaching position
TeachPosition(scanner, robot, configFile)

# change and test bacground position !!!
