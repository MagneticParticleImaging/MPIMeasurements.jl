export ArduinoGaussMeter, ArduinoGaussMeterParams, ArduinoGaussMeterDirectParams, ArduinoGaussMeterPoolParams, ArduinoGaussMeterDescriptionParams, getRawXYZValues, getXYZValues,triggerMeasurment, receive, receiveMeasurment, setSampleSize, getSampleSize, getTemperature


abstract type ArduinoGaussMeterParams <: DeviceParams end


Base.@kwdef struct ArduinoGaussMeterDirectParams <: ArduinoGaussMeterParams
  portAddress::String
  position::Int64 = 1
  calibration::Matrix{Float64} = Matrix{Float64}(I, (3, 3)) * 0.125
  rotation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  translation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  biasCalibration = Vector{Float64} = [0.0, 0.0, 0.0]
  sampleSize::Int
  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterDirectParams(dict::Dict) = params_from_dict(ArduinoGaussMeterDirectParams, dict)


Base.@kwdef struct ArduinoGaussMeterDescriptionParams <: ArduinoGaussMeterParams
  description::String
  positionID::Int
  position::Vector{Float64} = [0.0, 0.0, 0.0]
  calibration::Matrix{Float64} = Matrix{Float64}(I, (3, 3)) * 0.125
  rotation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  translation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  biasCalibration::Vector{Float64} = [0.0, 0.0, 0.0]
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
  sampleSize::Int = 0
  measdelay = 1000
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
  gauss.measdelay = parse(Int64, queryCommand(ard, "DELAY*"))
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
    """todo fix number"""
    if !(startswith(reply, "HALLSENS:"))
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
  
  triggerMeasurment(gauss)
  data = receive(gauss)
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


"""
  triggerMeasurment(gauss::ArduinoGaussMeter)
  start measurment in sensor 'gauss' 
  """
function triggerMeasurment(gauss::ArduinoGaussMeter)
  if gauss.measurementTriggered
    throw("measurement already triggered")
  end
  sendCommand(gauss.ard, "DATA")
  gauss.measurementTriggered = true
end


"""
  receive(gauss::ArduinoGaussMeter)::Array{Float64,1}
  
    collecting the measurment data for sensor 'gauss'
    triggerMeasurment(gauss::ArduinoGaussMeter) has to be called first. 
    
  #returns 
    [x_raw_mean,y_raw_mean,z_raw_mean, x_raw_var,y_raw_var,z_raw_var]
"""

function receive(gauss::ArduinoGaussMeter)
  if !gauss.measurementTriggered
    throw("triggerMeasurment(gauss::ArduinoGaussMeter) has to be called first")
  else
    temp = get_timeout(gauss.ard)
    timeout_ms = max(1000, floor(Int, gauss.sampleSize * gauss.measdelay * 1.2) + 1)
    set_timeout(gauss.ard, timeout_ms)
    try
      data_strings = split(receive(gauss.ard), ",")
      data = [parse(Float64, str) for str in data_strings]
      return data
    finally
      set_timeout(gauss.ard, temp)
    gauss.measurementTriggered = false
    end
  end
end

"""
receiveMeasurment(gauss::ArduinoGaussMeter)::Array{Float64,1}
  collecting, calibrating and returning measurment for 'gauss'-sensor in mT
    triggerMeasurment(gauss::ArduinoGaussMeter) has to be called first. 

  
  #return
    [x_mean,y_mean,z_mean, x_var,y_var,z_var]
"""
receiveMeasurment(gauss::ArduinoGaussMeter) = applyCalibration(gauss, receive(gauss))

"""
applyCalibration(gauss::ArduinoGaussMeter, data::Vector{Float64})::Array{Float64,1}

calibrate and rotate raw data to mT

Varianz can't be calibrated

#returns
[x_mean_c,y_mean_c,z_mean_c]
"""
function applyCalibration(gauss::ArduinoGaussMeter, data::Vector{Float64})
  means = data[1:3]
  # TODO Sanity checks on data, does it have the expected size
  calibrated_means = gauss.params.rotation * ((gauss.params.calibration * means) - gauss.params.biasCalibration)
  return calibrated_means
end


"""
setSampleSize(gauss::ArduinoGaussMeter, sampleSize::Int)::Int

sets sample size for measurment

  #Arguments 
  -`sampleSize` number of mesurments done by the sensor 1=>sample_size<=1024
  -`gauss` sensor

  #return
  -updatedSampleSize
"""
function setSampleSize(gauss::ArduinoGaussMeter, sampleSize::Int)
  data_string = queryCommand(gauss.ard, "SAMPLES" * string(sampleSize))
  updatedSampleSize = parse(Int, data_string)
  if (updatedSampleSize !== sampleSize)
    throw(error("wrong sample size set"))
  end
  gauss.sampleSize = updatedSampleSize
  return updatedSampleSize
end

function getSampleSize(gauss::ArduinoGaussMeter)
  return gauss.sampleSize
end

"""
getTemperature(gauss::ArduinoGaussMeter)::Float32

returns tempreture of the sensor, do not expect a high tempreture resolution
"""
function getTemperature(gauss::ArduinoGaussMeter)
  temp_str = queryCommand(gauss.ard, "TEMP")
  return parse(Float32, temp_str)
end

getPosition(gauss::ArduinoGaussMeter) = gauss.params.position
close(gauss::ArduinoGaussMeter) = close(gauss.ard)