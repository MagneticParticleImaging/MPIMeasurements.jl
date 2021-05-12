export MPIScanner, getDAQ, getGaussMeter, getRobot, getSafety, getGeneralParams,
getSurveillanceUnit, getTemperatureSensor


function loadDeviceIfAvailable(params::Dict, deviceType, deviceName::String)
  device = nothing
  if haskey(params, deviceName)
    device = deviceType(params[deviceName])
  end
  return device
end

mutable struct MPIScanner
  file::String
  params::Dict
  generalParams::Dict
  daq::Union{AbstractDAQ,Nothing}
  robot::Union{Robot,Nothing}
  gaussmeter::Union{GaussMeter,Nothing}
  safety::Union{RobotSetup,Nothing}
  surveillanceUnit::Union{SurveillanceUnit,Nothing}
  temperatureSensor::Union{TemperatureSensor,Nothing}

  function MPIScanner(file::String; guimode=false)
    filename = joinpath(@__DIR__, "Configurations", file)
    params = TOML.parsefile(filename)
    generalParams = params["General"]

    @info "Init SurveillanceUnit"
    surveillanceUnit = loadDeviceIfAvailable(params, SurveillanceUnit, "SurveillanceUnit")

    @info "Init DAQ"   # Restart the DAQ if necessary
    waittime = 45
    daq = nothing
    try
      daq = loadDeviceIfAvailable(params, DAQ, "DAQ")
    catch e
      if hasResetDAQ(surveillanceUnit)
        @info "connection to DAQ could not be established! Restart (wait $(waittime) seconds...)!"
        resetDAQ(surveillanceUnit)
        sleep(waittime)
        daq = loadDeviceIfAvailable(params, DAQ, "DAQ")
      else
        rethrow()
      end
    end

    @info "Init Robot"
    if guimode
      params["Robot"]["doReferenceCheck"] = false
    end
    robot = loadDeviceIfAvailable(params, Robot, "Robot")
    @info "Init GaussMeter"
    gaussmeter = loadDeviceIfAvailable(params, GaussMeter, "GaussMeter")  
    @info "Init Safety"
    safety = loadDeviceIfAvailable(params, RobotSetup, "Safety") 
    @info "Init TemperatureSensor"
    temperatureSensor = loadDeviceIfAvailable(params, TemperatureSensor, "TemperatureSensor")   
    @info "All components initialized!"

    return new(file,params,generalParams,daq,robot,gaussmeter,safety,surveillanceUnit,temperatureSensor)
  end
end

function Base.close(scanner::MPIScanner)
  if scanner.robot != nothing
    close(scanner.robot)
  end
  if scanner.gaussmeter != nothing
    close(scanner.gaussmeter)
  end
  if scanner.surveillanceUnit != nothing
    close(scanner.surveillanceUnit)
  end
  if scanner.temperatureSensor != nothing
    close(scanner.temperatureSensor)
  end

end

getGeneralParams(scanner::MPIScanner) = scanner.generalParams
getDAQ(scanner::MPIScanner) = scanner.daq
getRobot(scanner::MPIScanner) = scanner.robot
getGaussMeter(scanner::MPIScanner) = scanner.gaussmeter
getSafety(scanner::MPIScanner) = scanner.safety
getSurveillanceUnit(scanner::MPIScanner) = scanner.surveillanceUnit
getTemperatureSensor(scanner::MPIScanner) = scanner.temperatureSensor
