export MPIScanner, getDAQ, getGaussMeter, getRobot, getSafety

type MPIScanner
  params::Dict
  daq::Union{AbstractDAQ,Void}
  robot::Union{Robot,Void}
  gaussmeter::Union{GaussMeter,Void}
  safty::Union{RobotSetup,Void}
  recoMethod::Function

  function MPIScanner(file::String)
    filename = Pkg.dir("MPIMeasurements","src","Scanner","Configurations",file)
    params = TOML.parsefile(filename)
    return new(params,nothing,nothing,nothing,nothing,()->())
  end
end

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
