using MPIMeasurements

startLeft = [-1.0 1.0 0.0]
startRight = [1.0 1.0 0.0]
scaleXYZ = [3.0, 3.5, 1.0]
#scaleXYZ = [1.0, 1.0, 1.0]
shiftX = [scaleXYZ[1]/4, 0.0,0.0]
# Letter T
posTs = (transpose([startLeft;
          1.0 1.0 0.0;
          0.0 1.0 0.0;
          0.0 -1.0 0.0]).*scaleXYZ)
aGT = ArbitraryPositions((posTs)Unitful.mm)

# Letter H
posHs = (transpose([startLeft;
                  -1.0 -1.0 0.0;
                  -1.0 0.0 0.0;
                  1.0 0.0 0.0
                  1.0 1.0 0.0
                  1.0 -1.0 0.0]).*scaleXYZ)
aGH = ArbitraryPositions((posHs)Unitful.mm)

# Letter E
posEs = (transpose([startRight;
                  startLeft;
                  -1.0 0.0 0.0;
                  1.0 0.0 0.0
                  -1.0 0.0 0.0;
                  -1.0 -1.0 0.0
                  1.0 -1.0 0.0]).*scaleXYZ)
aGE = ArbitraryPositions((posEs)Unitful.mm)

# Letter easy U
posUeasy = (transpose([startLeft;
                  -1.0 -1.0 0.0;
                  1.0 -1.0 0.0;
                  1.0 1.0 0.0]).*scaleXYZ)
aGEesay = ArbitraryPositions((posUeasy)Unitful.mm)

# Letter K
posKs = ((transpose([startLeft;
                  -1.0 -1.0 0.0;
                  -1.0 0.0 0.0;
                  0.0 1.0 0.0;
                  -1.0 0.0 0.0;
                  0.0 -1.0 0.0]).*scaleXYZ).+shiftX)
aGK = ArbitraryPositions((posKs)Unitful.mm)

# Letter U
Udown = -0.0
r = 1.0 - Udown
posUs = ((transpose([startLeft;
                  -1.0 Udown 0.0;
                  -r*cos(0.0) -r*sin(0.0)-Udown 0.0;
                  -r*cos(pi/8) -r*sin(pi/8)-Udown 0.0;
                  -r*cos(pi/4) -r*sin(pi/4)-Udown 0.0;
                  -r*cos(pi*3/8) -r*sin(pi*3/8)-Udown 0.0;
                  -r*cos(pi/2) -r*sin(pi/2)-Udown 0.0;
                  -r*cos(pi*5/8) -r*sin(pi*5/8)-Udown 0.0;
                  -r*cos(pi*6/8) -r*sin(pi*6/8)-Udown 0.0;
                  -r*cos(pi*7/8) -r*sin(pi*7/8)-Udown 0.0;
                  1.0 Udown 0.0;
                  startRight]).*scaleXYZ))
aGU = ArbitraryPositions((posUs)Unitful.mm)

println("Press Enter to continue")
res=readline()

positions=aGU
configFile="DummyScanner.toml"
scanner = MPIScanner(configFile)
robot = getRobot(scanner)
defaultVel = getDefaultVelocity(robot)
setup = getSafety(scanner)
for pos in positions
  isValid = checkCoords(setup, pos, getMinMaxPosX(robot))
end
for (index,pos) in enumerate(positions)
    moveAbsUnsafe(robot, pos, defaultVel)
end
