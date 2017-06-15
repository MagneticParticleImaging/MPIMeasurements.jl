export loadParams, saveParams, updateParams

function defaultMPSParams()
  params = Dict{String,Any}()
  params["measNumFrames"] = 10
  params["rxNumAverages"] = 10
  params["decimation"] = 8
  params["calibFieldToVolt"] = 19.5
  params["calibRefToField"] = 1
  params["studyName"] = "default"
  params["studyExperiment"] = 0
  params["studyDescription"] = "n.a."
  params["studySubject"] = "MNP sample"
  params["tracerName"] = "n.a."
  params["tracerBatch"] = "n.a."
  params["tracerVendor"] = "n.a."
  params["tracerVolume"] = 0.0
  params["tracerConcentration"] = 0.0
  params["tracerSolute"] = "Fe"
  params["scannerFacility"] = "Universitätsklinikum Hamburg-Eppendorf"
  params["scannerOperator"] = "default"
  params["scannerManufacturer"] = "IBI"
  params["scannerModel"] = "MPS1"
  params["scannerTopology"] = "MPS"
  params["dfStrength"] = 10e-3
  params["dfPhase"] = 0.0
  params["dfBaseFrequency"] = 125e6
  params["dfDivider"] = 4836

  return params
end

function saveParams(mps::MPS)
  filename = Pkg.dir("MPILib","src","MPS","MPS.ini")
  ini = Inifile()
  for (key,value) in mps.params
    set(ini, key, string(value) )
  end
  open(filename,"w") do fd
    write(fd, ini)
  end
end


function readParam{T}(ini::Inifile,key::String,default::T)
  param = get(ini,key)
  if param == :notfound
    return default
  else
    return parse(T,param)
  end
end

function readParam(ini::Inifile,key::String,default::Bool)
  param = get(ini,key)
  if param == :notfound
    return default
  else
    return to_bool(param)
  end
end

function readParam(ini::Inifile,key::String,default::String)
  param = get(ini,key)
  if param == :notfound
    return default
  else
    return param
  end
end


function loadParams(mps::MPS)
  filename = Pkg.dir("MPILib","src","MPS","MPS.ini")

  ini = Inifile()

  if isfile(filename)
    read(ini, filename)
  end

  for key in keys(mps.params)
    mps.params[key] = readParam(ini, key, mps.params[key])
  end
end

function updateParams(mps::MPS,params::Dict)

  for key in keys(params)
    mps.params[key] = params[key]
  end

end
