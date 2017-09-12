export MPIScanner

type MPIScanner
  params::Dict
  daq::Union{AbstractDAQ,Void}
  robot::Union{AbstractRobot,Void}
  gaussmeter::Union{AbstractGaussMeter,Void}
  recoMethod::Function
  robotSetup::Union{RobotSetup,Void}
  function MPIScanner(file::String)
    filename = Pkg.dir("MPIMeasurements","src","Scanner","Configurations",file)
    params = TOML.parsefile(filename)

    if !haskey(params, "DAQ")
      warn("MPI Scanner has no DAQ installed!")
      daq = nothing
    else
        daq = DAQ(params["DAQ"])
    end

    if !haskey(params, "Robot")
      warn("MPI Scanner has no Robot installed!")
      robot = nothing
    else
      robot = Robot(params["Robot"])
    end

    if !haskey(params, "Gaussmeter")
      warn("MPI Scanner has no Gaussmeter installed!")
      gaussMeter = nothing
    else
      gaussMeter = nothing
    end

    if !haskey(params, "Safety")
        warn("MPI Scanner has no robotSetup installed!")
        robotSetup = nothing
    else
        robotSetup = RobotSetup(params["Safety"])
    end

    return new(params,daq,robot,gaussMeter,()->())
  end
end
