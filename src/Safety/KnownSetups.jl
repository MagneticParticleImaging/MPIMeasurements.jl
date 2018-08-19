export deltaSample, samplePhantom, hallSensor, mouseAdapter,customPhantom
export deltaSample3D, samplePhantom3D, hallSensor3D, mouseAdapter3D,customPhantom3D
export brukerCoil, mouseCoil, headCoil, ratCoil, clearance
export dSampleRegularScanner, mouseAdapterRegularScanner, dSampleMouseScanner,
mouseAdapterMouseScanner, hallSensorRegularScanner, hallSensorMouseScanner, getValidRobotSetups,
 getValidScannerGeos, getValidObjects, getValidHeadScannerGeos, getValidHeadObjects

# create given geometries
hallSensor = Circle(36.0Unitful.mm, "Hall Sensor");
deltaSample = Circle(10.0Unitful.mm, "Delta sample");
samplePhantom = Rectangle(65.0Unitful.mm,40.0Unitful.mm, "Sample Phantom")
mouseAdapter = Circle(38.0Unitful.mm, "Mouse adapter");
customPhantom = Rectangle(70.0Unitful.mm,70.0Unitful.mm, "Custom Phantom")

deltaSample3D = Cylinder(deltaSample, 495.0Unitful.mm,"Delta sample 3D");
hallSensor3D = Cylinder(hallSensor, 450.0Unitful.mm, "Hall Sensor 3D");
mouseAdapter3D = Cylinder(mouseAdapter, 500.0Unitful.mm, "Mouse adapter 3D")
samplePhantom3D = Cuboid(samplePhantom, 520.0Unitful.mm, "Sample Phantom 3D");
customPhantom3D = Cuboid(customPhantom, 520.0Unitful.mm, "Custom Phantom 3D")

# create given scanner diameter
const brukerScannerLength = 600.0Unitful.mm
brukerCoil = ScannerGeo(regularBrukerScannerdiameter, "Burker Coil", brukerScannerLength, deltaSample3D);
mouseCoil = ScannerGeo(40.0Unitful.mm, "Mouse Coil", brukerScannerLength, deltaSample3D);
ratCoil = ScannerGeo(72.0Unitful.mm, "Rat Coil", brukerScannerLength, deltaSample3D)
#headCoil = ScannerGeo(170.0Unitful.mm, "Head Coil", -65.0Unitful.mm, 365.0Unitful.mm);

headCoil = ScannerGeo(170.0Unitful.mm, "Head Coil", 180.0Unitful.mm, deltaSample3D);

# standard clearance
clearance = Clearance(1.0Unitful.mm);

validScannerGeos = [brukerCoil, mouseCoil, ratCoil, headCoil]
validObjects = [deltaSample3D, hallSensor3D, mouseAdapter3D, samplePhantom3D]

validHeadScannerGeos = [headCoil]
validHeadObjects = [samplePhantom3D, deltaSample3D, hallSensor3D, customPhantom3D]

# Standard Combination RobotSetup
dSampleRegularScanner = RobotSetup("dSampleRegularScanner", deltaSample3D, brukerCoil, clearance);
mouseAdapterRegularScanner = RobotSetup("mouseAdapterRegularScanner", mouseAdapter3D, brukerCoil, clearance);
dSampleMouseScanner = RobotSetup("dSampleMouseScanner", deltaSample3D, mouseCoil, clearance);
mouseAdapterMouseScanner = RobotSetup("mouseAdapterMouseScanner", mouseAdapter3D, mouseCoil, clearance);
dSampleRatScanner = RobotSetup("dSampleRatScanner", deltaSample3D, ratCoil, clearance);
mouseAdapterRatScanner = RobotSetup("mouseAdapterRatScanner", mouseAdapter3D, ratCoil, clearance);
hallSensorRegularScanner = RobotSetup("hallSensorRegularScanner", hallSensor3D, brukerCoil, clearance)
hallSensorMouseScanner = RobotSetup("hallSensorMouseScanner", hallSensor3D, mouseCoil, clearance)
hallSensorRatScanner = RobotSetup("hallSensorMouseScanner", hallSensor3D, ratCoil, clearance)

validRobotSetups = [dSampleRegularScanner, mouseAdapterRegularScanner, dSampleMouseScanner, mouseAdapterMouseScanner,
 dSampleRatScanner, mouseAdapterRatScanner, hallSensorRegularScanner, hallSensorMouseScanner, hallSensorRatScanner]

"Returns all validated Scanner Coils!"
function getValidScannerGeos()
    return validScannerGeos
end

"Returns all validated Objects!"
function getValidObjects()
   return validObjects
end

"Returns all validated Robot Setups!"
function getValidRobotSetups()
    return validRobotSetups
end

"Returns all validated Head Scanner!"
function getValidHeadScannerGeos()
    return validHeadScannerGeos
end

"Returns all validated Head Objects!"
function getValidHeadObjects()
   return validHeadObjects
end
