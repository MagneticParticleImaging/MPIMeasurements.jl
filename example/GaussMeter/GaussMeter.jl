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
println("")

println("Step 1: Set up Gaussmeter")
while input("Ready?(y): ") != "y"
end

#println("")
#println("Step 2: Select the Port of the Gaussmeter")
#println("-------------------------------------------")
#list_ports()
#println("-------------------------------------------")
#port = input("Choose Port: ")


# define Grid
rG = CartesianGridPositions([2,2,2],[3.0,3.0,3.0]u"mm",[0.0,0.0,0.0]u"mm")

# create Scanner
bR = brukerRobot("RobotServer")
bS = Scanner{BrukerRobot}(:BrukerScanner, bR, dSampleRegularScanner, ()->())

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gaussMeter::MPIMeasurements.SerialDevice{MPIMeasurements.GaussMeter}
  positions::Array{Vector{typeof(1.0u"mm")},1}
  magneticField::Array{Vector{typeof(1.0u"mT")},1}
end
mfMeasObj = MagneticFieldMeas(gaussMeter("/dev/ttyUSB0"),Array{Vector{typeof(1.0u"mm")},1}(),Array{Vector{typeof(1.0u"mT")},1}())

setStandardSettings(mfMeasObj.gaussMeter)

# define preMoveAction
function preMA(measObj::MagneticFieldMeas, pos::Array{typeof(1.0u"mm"),1})
  println("pre action: ", pos)

end

#!!!!Denk an die Verschiebung zwischen x y z!!!!!

# define postMoveAction
function postMA(measObj::MagneticFieldMeas, pos::Array{typeof(1.0u"mm"),1})
  println("post action: ", pos)
  push!(measObj.positions, pos)
  magValues=[getXValue(measObj.gaussMeter), getYValue(measObj.gaussMeter), getZValue(measObj.gaussMeter)]*u"mT"
  #magValues =[1.0u"mT",2.0u"mT",1.0u"mT"]
  push!(measObj.magneticField, magValues)
end

res = acquireMeas!(bS, rG, mfMeasObj, preMA, postMA)

positionsArray=hcat(res.positions...)
magArray=hcat(res.magneticField...)
