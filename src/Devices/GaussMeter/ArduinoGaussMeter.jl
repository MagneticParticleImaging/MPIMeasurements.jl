export ArduinoGaussMeter, ArduinoGaussMeterParams, ArduinoGaussMeterDirectParams, ArduinoGaussMeterPoolParams, ArduinoGaussMeterDescriptionParams, getRawXYZValues, getXValue, triggerMeasurment, reciveMeasurmentRaw, reciveMeasurment, setSampleSize, getSampleSize, getTemperature
abstract type ArduinoGaussMeterParams <: DeviceParams end


Base.@kwdef struct ArduinoGaussMeterDirectParams <: ArduinoGaussMeterParams
  portAddress::String
  position::Int64 = 1
  calibration::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  rotation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  translation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  biasCalibration = Vector{Float64} = [0.098, 0.098, 0.098]
  sampleSize::Int
  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterDirectParams(dict::Dict) = params_from_dict(ArduinoGaussMeterDirectParams, dict)


Base.@kwdef struct ArduinoGaussMeterDescriptionParams <: ArduinoGaussMeterParams
  description::String
  position::Int64 = 1
  calibration::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  rotation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  translation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  biasCalibration::Vector{Float64} = [0.098, 0.098, 0.098]
  sampleSize::Int

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end

function ArduinoGaussMeterDescriptionParams(dict::Dict)
  if haskey(dict, "translation")
    dict["translation"] = Float64.(reshape(dict["translation"], 3, 3))
  end
  if haskey(dict, "rotation")
    dict["rotation"] = Float64.(reshape(dict["rotation"], 3, 3))
  end
  if haskey(dict, "calibration")
    dict["calibration"] = Float64.(reshape(dict["calibration"], 3, 3))
  end
  params_from_dict(ArduinoGaussMeterDescriptionParams, dict)
end


Base.@kwdef mutable struct ArduinoGaussMeter <: GaussMeter
  @add_device_fields ArduinoGaussMeterParams
  ard::Union{SimpleArduino,Nothing} = nothing
  rotatedCalibration::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  sampleSize::Int = 0
  measurementTriggered::Bool = false
end

neededDependencies(::ArduinoGaussMeter) = []
optionalDependencies(::ArduinoGaussMeter) = [SerialPortPool]

function _init(gauss::ArduinoGaussMeter)
  params = gauss.params
  sd = initSerialDevice(gauss, params)
  @info "Connection to ArduinoGaussMeter established."
  ard = SimpleArduino(; commandStart=params.commandStart, commandEnd=params.commandEnd, sd=sd)
  gauss.ard = ard
  gauss.rotatedCalibration = params.rotation * params.calibration
  setSampleSize(gauss, params.sampleSize)
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterDirectParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(gauss, sd)
  return sd
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterDescriptionParams)
  sd = initSerialDevice(gauss, params.description)
  checkSerialDevice(gauss, sd)
  return sd
end

function checkSerialDevice(gauss::ArduinoGaussMeter, sd::SerialDevice)
  try
    reply = query(sd, "!VERSION*")
    if !(startswith(reply, "HALLSENS:2"))
      close(sd)
      throw(ScannerConfigurationError(string("Connected to wrong Device", reply)))
    end
    return sd
  catch e
    throw(ScannerConfigurationError("Could not verify if connected to correct device"))
  end
end

"""
  getRawXYZValues(gauss::ArduinoGaussMeter)::Array{Float64,1}
  
  start measurment in sensor 'gauss' and returns raw measurment
  
  #returns 
    [x_raw_mean,y_raw_mean,z_raw_mean, x_raw_var,y_raw_var,z_raw_var]
"""
function getRawXYZValues(gauss::ArduinoGaussMeter)
  temp = get_timeout(gauss.ard)
  timeout_ms = max(1000, floor(Int, gauss.sampleSize * 10 * 1.2) + 1)
  set_timeout(gauss.ard, timeout_ms)
  data_strings = split(sendCommand(gauss.ard, "DATA"), ",")
  data = [parse(Float64, str) for str in data_strings]
  set_timeout(gauss.ard, temp)
  return data
end

"""
  getXYZValues(gauss::ArduinoGaussMeter)::Array{Float64,1}
  start and returns calibrated measurment for 'gauss'-sensor in mT
  
  #returns 
    [x_mean,y_mean,z_mean, x_var,y_var,z_var]
"""
function getXYZValues(gauss::ArduinoGaussMeter)
  data = getRawXYZValues(gauss)
  return applyCalibration(gauss, data)
end

#todo move to Arduino.jl
"""
  triggerMeasurment(gauss::ArduinoGaussMeter)
  start measurment in sensor 'gauss' 
"""
function triggerMeasurment(gauss::ArduinoGaussMeter)
  cmd = cmdStart(gauss.ard) * "DATA" * cmdEnd(gauss.ard)
  sd = gauss.ard.sd
  lock(sd.sdLock)
  try
    if gauss.measurementTriggered
      throw("measurement already triggered")
    end
    sp_flush(sd.sp, SP_BUF_INPUT)
    send(sd, cmd)
    gauss.measurementTriggered = true
  finally
    unlock(sd.sdLock)
  end
end


"""
  reciveMeasurmentRaw(gauss::ArduinoGaussMeter)::Array{Float64,1}
  
    collecting the measurment data for sensor 'gauss'
    triggerMeasurment(gauss::ArduinoGaussMeter) has to be called first. 
    
  #returns 
    [x_raw_mean,y_raw_mean,z_raw_mean, x_raw_var,y_raw_var,z_raw_var]
"""
function reciveMeasurmentRaw(gauss::ArduinoGaussMeter)
  #todo use lock
  if !gauss.measurementTriggered
    throw("triggerMeasurment(gauss::ArduinoGaussMeter) has to be called first")
  else
    sd = gauss.ard.sd
    lock(sd.sdLock)
    temp = get_timeout(gauss.ard)
    timeout_ms = max(1000, floor(Int, gauss.sampleSize * 10 * 1.2) + 1)
    set_timeout(gauss.ard, timeout_ms)
    try
      data_strings = split(receive(gauss.ard.sd), ",")
      data = [parse(Float64, str) for str in data_strings]
      return data
    finally
      sp_flush(sd.sp, SP_BUF_INPUT)
      unlock(sd.sdLock)
      set_timeout(gauss.ard, temp)
      gauss.measurementTriggered = false
    end
  end
end

"""
reciveMeasurment(gauss::ArduinoGaussMeter)::Array{Float64,1}
  collecting, calibrating and returning measurment for 'gauss'-sensor in mT
    triggerMeasurment(gauss::ArduinoGaussMeter) has to be called first. 

  
  #return
    [x_mean,y_mean,z_mean, x_var,y_var,z_var]
"""
reciveMeasurment(gauss::ArduinoGaussMeter) = applyCalibration(gauss, reciveMeasurmentRaw(gauss))

"""
applyCalibration(gauss::ArduinoGaussMeter, data::Vector{Float64})::Array{Float64,1}

calibrate and rotated raw data to mT
"""
function applyCalibration(gauss::ArduinoGaussMeter, data::Vector{Float64})
  means = data[1:3]
  var = data[4:6]
  calibrated_means = gauss.rotatedCalibration * means + gauss.params.biasCalibration
  calibrated_var = gauss.params.coordinateTransformation * gauss.params.coordinateTransformation * var
  return vcat(calibrated_means, calibrated_var)
end

"""
  setSampleSize(gauss::ArduinoGaussMeter, sampleSize::Int)::Int = sample_size

  sets sample size for measurment

  #Arguments 
  -`sampleSize` number of mesurments done by the sensor 1=>sample_size<=1024
  -`gauss` sensor

  #return
  -sampleSize()::Int
"""
function setSampleSize(gauss::ArduinoGaussMeter, sampleSize::Int)
  if (sampleSize > 1024 || sampleSize < 1)
    throw(error("no valid sample size, pick size from 1 to 1024"))
  end
  gauss.sampleSize = sampleSize
  data_string = sendCommand(gauss.ard, "SAMPLES" * string(sampleSize))
  return parse(Int, data_string)
end

function getSampleSize(gauss::ArduinoGaussMeter)
  return gauss.sampleSize
end

"""
getTemperature(gauss::ArduinoGaussMeter)::Float32

returns tempreture of the sensor, do not expect a high tempreture resolution
"""
function getTemperature(gauss::ArduinoGaussMeter)
  temp_str = sendCommand(gauss.ard, "TEMP")
  return parse(Float32, temp_str)
end

close(gauss::ArduinoGaussMeter) = close(gauss.ard)