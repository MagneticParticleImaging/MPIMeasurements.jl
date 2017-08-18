using MPIMeasurements
using Base.Test
using Unitful
using Compat

#using LibSerialPort

function input(prompt::String="")
  print(prompt)
  return chomp(readline())
end

function inputInt(prompt::String)
  print(prompt)
  return parse(Int64, readline())
end

function inputFloat(prompt::String)
  print(prompt)
  return parse(Float64, readline())
end

println("------------------")
println("| New Measurment |")
println("------------------")
println()

# define Grid
rG = loadTDesign(3,8,30u"mm")

# create Scanner
bR = brukerRobot("RobotServer")
bS = Scanner{BrukerRobot}(:BrukerScanner, bR, hallSensorRegularScanner, ()->())

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gaussMeter::MPIMeasurements.SerialDevice{MPIMeasurements.GaussMeter}
  positions::Vector{Vector{typeof(1.0u"m")}}
  magneticField::Vector{Vector{typeof(1.0u"T")}}
end
mfMeasObj = MagneticFieldMeas(gaussMeter("/dev/ttyUSB0"),Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())

# Initialize GaussMeter with standard settings
setStandardSettings(mfMeasObj.gaussMeter)

# define preMoveAction
function preMA(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
  println("pre action: ", pos)

end

#!!!!Denk an die Verschiebung zwischen x y z!!!!!

# define postMoveAction
function postMA(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
  println("post action: ", pos)
  sleep(1.0)
  push!(measObj.positions, pos)
  magValues=[getXValue(measObj.gaussMeter), getYValue(measObj.gaussMeter), getZValue(measObj.gaussMeter)]*u"T"
  #magValues =[1.0u"mT",2.0u"mT",1.0u"mT"]
  push!(measObj.magneticField, magValues)
end

res = acquireMeas!(bS, rG, mfMeasObj, preMA, postMA)

#move back to park position after measurement has finished
movePark(bS)

#positionsArray=hcat(res.positions...)
#magArray=hcat(res.magneticField...)
