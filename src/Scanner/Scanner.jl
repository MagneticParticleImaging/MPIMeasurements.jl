export MPIScanner, getDAQ, getGaussMeter, getRobot, getSafety, getGeneralParams,
      getSurveillanceUnit

type MPIScanner
  params::Dict
  generalParams::Dict
  daq::Union{AbstractDAQ,Void}
  robot::Union{Robot,Void}
  gaussmeter::Union{GaussMeter,Void}
  safty::Union{RobotSetup,Void}
  surveillanceUnit::Union{SurveillanceUnit,Void}
  recoMethod::Function

  function MPIScanner(file::String)
    filename = Pkg.dir("MPIMeasurements","src","Scanner","Configurations",file)
    params = TOML.parsefile(filename)
    generalParams = params["General"]
    return new(params,generalParams,nothing,nothing,nothing,nothing,nothing,()->())
  end
end

getGeneralParams(scanner::MPIScanner) = scanner.generalParams

function getDAQ(scanner::MPIScanner)
  if !haskey(scanner.params, "DAQ")
    error("MPI Scanner has no DAQ installed!")
  end
  if scanner.daq == nothing
    scanner.daq = DAQ(scanner.params["DAQ"])
  end
  return scanner.daq
end

function getRobot(scanner::MPIScanner)
  if !haskey(scanner.params, "Robot")
    error("MPI Scanner has no Robot installed!")
  end
  if scanner.robot == nothing
    scanner.robot = Robot(scanner.params["Robot"])
  end
  return scanner.robot
end

function getGaussMeter(scanner::MPIScanner)
  if !haskey(scanner.params, "GaussMeter")
    error("MPI Scanner has no GaussMeter installed!")
  end
  if scanner.gaussmeter == nothing
    scanner.gaussmeter = GaussMeter(scanner.params["GaussMeter"])
  end
  return scanner.gaussmeter
end

function getSafety(scanner::MPIScanner)
  if !haskey(scanner.params, "Safety")
    error("MPI Scanner has no Safety Module installed!")
  end
  if scanner.safty == nothing
    scanner.safty = RobotSetup(scanner.params["Safety"])
  end
  return scanner.safty
end

function getSurveillanceUnit(scanner::MPIScanner)
  if !haskey(scanner.params, "SurveillanceUnit")
    error("MPI Scanner has no SurveillanceUnit installed!")
  end
  if scanner.surveillanceUnit == nothing
    scanner.surveillanceUnit = SurveillanceUnit(scanner.params["SurveillanceUnit"])
  end
  return scanner.surveillanceUnit
end
