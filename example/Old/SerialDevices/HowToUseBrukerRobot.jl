# In this usecase you just want to move the robot around in single steps and do NOT want to perform a tour!

# 1. Open terminal from within the Paravision software
using MPIMeasurements

# 2. select safety object depending on the setup you have chosen for your experiment
# select a combination of AdapterType and ScannerType
# AdapterType:          Scannertype:
# deltaSample3D		brukerCoil
# hallSensor3D		mouseCoil
# mouseAdapter3D	ratCoil
# Display all possible setup combinations
validsetups = getValidRobotSetups();
for (k,s) in enumerate(validsetups)
   println(k,". ",s.name)
end
# e.g. select the mouseAdapterMouseScanner
safety = mouseAdapterMouseScanner

# 3. get scanner and robot
scanner = MPIScanner("BrukerScanner.toml")
robot = getRobot(scanner)

# 4. perform the moveAbs robot movement
moveAbs(robot, safety, [220.0,0.0,0.0]*u"mm")

############################################################
# In this usecase you can also use the performtour! function
# As an alternative you can a change the "BrukerScanner.toml" directly and change the attributes under
# [Safety]
# receiveCoil = "?"
# robotMount = "?"

# Choose coil setup
coils = getValidScannerGeos();
for (k,c) in enumerate(coils)
   println(c.name)
end
# e.g.
# receiveCoil = "mouseCoil"

# Choose robotMount setup
mounts = getValidObjects();
for (k,m) in enumerate(mounts)
   println(m.name)
end
# e.g.
# robotMount = "mouseAdapter3D"

# Then you can use the safety from the "BrukerScanner.toml"
# 1. get scanner and robot
using MPIMeasurements
scanner = MPIScanner("BrukerScanner.toml")
robot = getRobot(scanner)
safety = getSafety(scanner)

# 2. perform the moveAbs robot movement
moveAbs(robot, safety, [220.0,0.0,0.0]*u"mm")


