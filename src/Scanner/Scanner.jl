export MPIScanner, getDAQ, getRobot, getGaussmeter

type MPIScanner
  params::Dict
  function MPIScanner(file::String)
    filename = Pkg.dir("MPIMeasurements","src","Scanner","Configurations",file)
    params = TOML.parsefile(filename)
    return new(params)
  end
end

function getDAQ(scanner::MPIScanner)
  if !haskey(scanner.params, "DAQ")
    error("MPI Scanner has no DAQ installed!")
  end
  return DAQ(scanner.params["DAQ"])
end


function getRobot(scanner::MPIScanner)
  if !haskey(scanner.params, "Robot")
    error("MPI Scanner has no Robot installed!")
  end
  return # ????? (scanner.params["DAQ"])
end

function getGaussmeter(scanner::MPIScanner)
  if !haskey(scanner.params, "Gaussmeter")
    error("MPI Scanner has no Gaussmeter installed!")
  end
  return # ????? (scanner.params["DAQ"])
end
