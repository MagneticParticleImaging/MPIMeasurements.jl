using MPIMeasurements

startLeft = [-1.0 1.0 0.0]
startRight = [1.0 1.0 0.0]
scaleXYZ = [30.0, 34.0, 1.0]
center=[13.0, 0.0, -5.0]

#scaleXYZ = [1.0, 1.0, 1.0]
shiftX = [scaleXYZ[1]/4, 0.0,0.0]

function rotateInvert(pos)
         temp = pos[1,:]
         pos[1,:] = -pos[2,:]
         pos[2,:] = temp
 return pos
end
# Letter T
posTs = (transpose([startLeft;
          1.0 1.0 0.0;
          0.0 1.0 0.0;
          0.0 -1.0 0.0]).*scaleXYZ.+center)
posTsRotIn=rotateInvert(posTs)
aGT = ArbitraryPositions((posTsRotIn)Unitful.mm)

# Letter H
posHs = (transpose([startLeft;
                  -1.0 -1.0 0.0;
                  -1.0 0.0 0.0;
                  1.0 0.0 0.0
                  1.0 1.0 0.0
                  1.0 -1.0 0.0]).*scaleXYZ.+center)
posHsRotIn=rotateInvert(posHs)
aGH = ArbitraryPositions((posHsRotIn)Unitful.mm)

# Letter E
posEs = (transpose([startRight;
                  startLeft;
                  -1.0 0.0 0.0;
                  1.0 0.0 0.0
                  -1.0 0.0 0.0;
                  -1.0 -1.0 0.0
                  1.0 -1.0 0.0]).*scaleXYZ.+center)
posEsRotIn=rotateInvert(posEs)
aGE = ArbitraryPositions((posEsRotIn)Unitful.mm)

# Letter easy U
posUeasy = (transpose([startLeft;
                  -1.0 -1.0 0.0;
                  1.0 -1.0 0.0;
                  1.0 1.0 0.0]).*scaleXYZ.+center)
posUeasyRotIn=rotateInvert(posUeasy)
aGEesay = ArbitraryPositions((posUeasy)Unitful.mm)

# Letter K
posKs = ((transpose([startLeft;
                  -1.0 -1.0 0.0;
                  -1.0 0.0 0.0;
                  1.0 1.0 0.0;
                  -1.0 0.0 0.0;
                  1.0 -1.0 0.0]).*scaleXYZ).+shiftX.+center)
posKsRotIn=rotateInvert(posKs)
aGK = ArbitraryPositions((posKsRotIn)Unitful.mm)

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
                  startRight]).*scaleXYZ.+center))
posUsRotIn=rotateInvert(posUs)
aGU = ArbitraryPositions((posUsRotIn)Unitful.mm)

println("Press Enter to continue")
res=readline()



configFile="HeadScanner.toml"
scanner = MPIScanner(configFile)
robot = getRobot(scanner)
defaultVel = getDefaultVelocity(robot)
setup = getSafety(scanner)
bG = ustrip.(parkPos(robot))
posBG = transpose([bG[1] bG[2] bG[3]])
bGA = ArbitraryPositions((posBG)Unitful.mm)

lettersUKE = [aGU,bGA,aGK,bGA,aGE,bGA]
lettersTUHH = [aGT,bGA,aGU,bGA,aGH,bGA,aGH,bGA]

letters=lettersUKE

for letter in letters
for pos in letter
  isValid = checkCoords(setup, pos, getMinMaxPosX(robot))
end
end
Dates.Time(Dates.now())
PosLog=Any[]
TimeLog=Any[]

setEnabled(robot, true)
#sleep(5)
for letter in letters
  for (index,pos) in enumerate(letter)
   TimeLog=push!(TimeLog,Dates.Time(Dates.now()))
   PosLog=cat(1,PosLog,pos')
   moveAbsUnsafe(robot, pos, defaultVel)
  end
end
