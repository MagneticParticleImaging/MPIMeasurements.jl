export loadParams, saveParams, updateParams

# The purpose of this function is to define the type of the entries
function defaultDAQParams()
  params = Dict{String,Any}()
  params["daq"] = "RedPitaya"
  params["ip"] = ["192.168.1.20"]
  params["acqNumFrames"] = 10
  params["acqNumAverages"] = 10
  params["decimation"] = 8
  params["calibFieldToVolt"] = 19.5
  params["calibRefToField"] = [1.0]
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
  params["scannerName"] = "MPS1"
  params["scannerTopology"] = "MPS"
  params["dfStrength"] = [10e-3]
  params["dfPhase"] = [0.0]
  params["dfBaseFrequency"] = 125e6
  params["dfDivider"] = [4800]
  params["rxNumChannels"] = 1
  params["controlPause"] = 0.5
  params["acqNumPatches"] = 1
  params["acqNumFFChannels"] = 1
  params["acqFFValues"] = [1.0]
  params["acqNumPeriods"] = 1
  params["acqFFLinear"] = false
  params["controlLoopPhaseAccuracy"] = 0.5
  params["controlLoopAmplitudeAccuracy"] = 0.01
  params["dfWaveform"] = "sine"
  params["measUnit"] = "V"
  params["measDataConversionFactor"] = [1.0, 0]
  params["measIsTransposed"] = false
  params["measIsBGCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFramePermutation"] = false
  params["measIsFrequencySelection"] = false
  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["studyIsSimulation"] = false
  params["studyIsCalibration"] = false
  params["rpGainSetting"] = [0, 0]

  return params
end

function saveParams(daq::AbstractDAQ)
  filename = configFile(daq)
  ini = Inifile()
  for (key,value) in daq.params
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

function readParam{T}(ini::Inifile,key::String,default::Vector{T})
  param = get(ini,key)
  if param == :notfound
    return default
  else
    return [parse(T,strip(path)) for path in split(param,",")]
  end
end

to_bool(s::AbstractString) = (lowercase(s) == "true") ? true : false
to_bool(b::Bool) = b

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

function readParam(ini::Inifile,key::String,default::Vector{String})
  param = get(ini,key)
  if param == :notfound
    return default
  else
    return [strip(path) for path in split(param,",")]
  end
end

function loadParams(filename)
  params = defaultDAQParams()
  ini = Inifile()

  if isfile(filename)
    read(ini, filename)
  end

  for key in keys(params)
    params[key] = readParam(ini, key, params[key])
  end
  return params
end

function updateParams(daq::AbstractDAQ,params::Dict)

  for key in keys(params)
    daq.params[key] = params[key]
  end

end
