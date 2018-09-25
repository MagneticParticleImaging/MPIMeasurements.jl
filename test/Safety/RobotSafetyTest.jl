@testset "Testing Robot Safety" begin
# Robot Constants

println(@test_throws ErrorException Circle(-0.5Unitful.mm,"test"))
println(@test_throws MethodError ScannerGeo(0.5Unitful.mm,"test3"))
println(@test_throws MethodError ScannerGeo(118.5Unitful.mm,"test3"))
println(@test_throws ErrorException DriveFieldAmplitude(15.0Unitful.mT, 14.0Unitful.mT, 14.0Unitful.mT))
println(@test_throws ErrorException GradientScan(2.6Unitful.T/Unitful.m))

posX=-90.0Unitful.mm
minRobotX = -100.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(deltaSample3D),minRobotX, maxRobotX)
@test errorStatus== :VALID

posX=-91.0Unitful.mm
minRobotX = -100.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(deltaSample3D),minRobotX, maxRobotX)
@test errorStatus== :INVALID

posX=-90.0Unitful.mm
minRobotX = -80.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(deltaSample3D),minRobotX, maxRobotX)
@test errorStatus== :INVALID

posX=200.0Unitful.mm
minRobotX = -80.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(deltaSample3D),minRobotX, maxRobotX)
@test errorStatus== :VALID

posX=201.0Unitful.mm
minRobotX = -80.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(deltaSample3D),minRobotX, maxRobotX)
@test errorStatus== :INVALID

posX=-90.0Unitful.mm
minRobotX = -100.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(samplePhantom3D),minRobotX, maxRobotX)
@test errorStatus== :INVALID

posX=-65.0Unitful.mm
minRobotX = -100.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(samplePhantom3D),minRobotX, maxRobotX)
@test errorStatus== :VALID

posX=-135.0Unitful.mm
minRobotX = -137.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(hallSensor3D),minRobotX, maxRobotX)
@test errorStatus== :VALID

posX=-136.0Unitful.mm
minRobotX = -137.0Unitful.mm
maxRobotX = 200.0Unitful.mm
errorStatus, errorX = checkCoordsX(posX,headCoil,length(hallSensor3D),minRobotX, maxRobotX)
@test errorStatus== :INVALID

posY=0.0Unitful.mm
posZ=52.0Unitful.mm
errorStatus, errorY,errorZ = checkCoordsYZ(deltaSample, brukerCoil.diameter/2, posY, posZ,clearance)
@test errorStatus==:VALID

posY=0.0Unitful.mm
posZ=53.0Unitful.mm
errorStatus, errorY,errorZ = checkCoordsYZ(deltaSample, brukerCoil.diameter/2, posY, posZ,clearance)
@test errorStatus==:INVALID

posY=0.0Unitful.mm
posZ=30.0Unitful.mm
errorStatus, errorY,errorZ = checkCoordsYZ(samplePhantom, brukerCoil.diameter/2, posY, posZ,clearance)
@test errorStatus==:VALID

posY=0.0Unitful.mm
posZ=31.0Unitful.mm
errorStatus, errorY,errorZ = checkCoordsYZ(samplePhantom, brukerCoil.diameter/2, posY, posZ,clearance)
@test errorStatus==:INVALID

posY=24.0Unitful.mm
posZ=0.0Unitful.mm
errorStatus, errorY,errorZ = checkCoordsYZ(samplePhantom, brukerCoil.diameter/2, posY, posZ,clearance)
@test errorStatus==:VALID

posY=25.0Unitful.mm
posZ=0.0Unitful.mm
errorStatus, errorY,errorZ = checkCoordsYZ(samplePhantom, brukerCoil.diameter/2, posY, posZ,clearance)
@test errorStatus==:INVALID

headScanner=RobotSetup("Head Scanner",deltaSample3D, headCoil, clearance)
minMaxRobotX=[-65.0Unitful.mm,200.0Unitful.mm]
coords =[0.0 0.0 0.0]Unitful.mm
tableCoords=checkCoords(headScanner, coords, minMaxRobotX)
@test tableCoords[2,1]==:VALID

headScanner=RobotSetup("Head Scanner",samplePhantom3D, headCoil, clearance)
minMaxRobotX=[-65.0Unitful.mm,200.0Unitful.mm]
coords =[0.0 0.0 0.0]Unitful.mm
tableCoords=checkCoords(headScanner, coords, minMaxRobotX)
@test tableCoords[2,1]==:VALID

end
