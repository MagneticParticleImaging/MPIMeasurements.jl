export ArduinoGaussMeter, ArduinoGaussMeterParams, ArduinoGaussMeterDirectParams, ArduinoGaussMeterPoolParams, ArduinoGaussMeterDescriptionParams
abstract type ArduinoGaussMeterParams <: DeviceParams end

# Params need more paramters
# TODO three matrices:
# calibration: 3x3 <- from calibration measurement (in hall sensor coords) 
# rotation: 3x3 <- how the sensor is rotated in the cube
# translation: 3x3 <- spatial offset of each sensor (for now 0)
# TODO each params needs a position value
# TODO "getter" for rotated translation

Base.@kwdef struct ArduinoGaussMeterDirectParams <: ArduinoGaussMeterParams
  portAddress::String
  position::Int64 = 1
  calibration::Matrix{Float64}
  rotation::Matrix{Float64}
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterDirectParams(dict::Dict) = params_from_dict(ArduinoGaussMeterDirectParams, dict)

Base.@kwdef struct ArduinoGaussMeterPoolParams <: ArduinoGaussMeterParams
  position::Int64
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterPoolParams(dict::Dict) = params_from_dict(ArduinoGaussMeterPoolParams, dict)

Base.@kwdef struct ArduinoGaussMeterDescriptionParams <: ArduinoGaussMeterParams
  description::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]
  sampleSize:: Int

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
function ArduinoGaussMeterDescriptionParams(dict::Dict)
  if haskey(dict, "coordinateTransformation")
    dict["coordinateTransformation"] = reshape(dict["coordinateTransformation"], 3, 3)
  end 
  params_from_dict(ArduinoGaussMeterDescriptionParams, dict)
end


Base.@kwdef mutable struct ArduinoGaussMeter <: GaussMeter
  @add_device_fields ArduinoGaussMeterParams
  ard::Union{SimpleArduino, Nothing} = nothing
  rotatedCalibration::Matrix{Float64}
  sampleSize::Int = 0
end

neededDependencies(::ArduinoGaussMeter) = []
optionalDependencies(::ArduinoGaussMeter) = [SerialPortPool]

function _init(gauss::ArduinoGaussMeter)
  params = gauss.params
  sd = initSerialDevice(gauss, params)
  @info "Connection to ArduinoGaussMeter established."        
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, sd = sd)
  gauss.ard = ard
  gauss.rotatedCalibration = params.rotation * params.calibration
  setSampleSize(gauss, params.sampleSize)
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterDirectParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(gauss, sd)
  return sd
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterPoolParams)
  return initSerialDevice(gauss, "!VERSION*", "HALLSENS:1:$(params.position)")
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

function getXYZValues(gauss::ArduinoGaussMeter)
  temp = get_timeout(gauss.ard)
  timeout_ms = max(1000,floor(Int,gauss.sampleSize*10*1.2)+1)
  @info(timeout_ms)
  set_timeout(gauss.ard, timeout_ms)
  data_strings = split(sendCommand(gauss.ard, "DATA"), ",")
  # TODO use rotatedCalibration * data
  data = [parse(Float32,str) for str in data_strings]
  set_timeout(gauss.ard, temp)
  return data
end

export setSampleSize
function setSampleSize(gauss::ArduinoGaussMeter, sampleSize::Int)
  if(sampleSize>1024 || sampleSize<1)
    throw(error("no valid sample size, pick size from 1 to 1024"))
  end
  gauss.sampleSize = sampleSize
  data_string = sendCommand(gauss.ard, "SAMPLES" * string(sampleSize))
  return parse(Int, data_string)
end

export getSampleSize
function  getSampleSize(gauss::ArduinoGaussMeter)
  return gauss.sampleSize
end



export getTemperature
function getTemperature(gauss::ArduinoGaussMeter)
  temp_str = sendCommand(gauss.ard, "TEMP")
  return parse(Float32,temp_str)
end

close(gauss::ArduinoGaussMeter) = close(gauss.ard)