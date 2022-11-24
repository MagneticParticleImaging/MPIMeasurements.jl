export ArduinoGaussMeter, ArduinoGaussMeterParams, ArduinoGaussMeterDirectParams, ArduinoGaussMeterPoolParams, ArduinoGaussMeterDescriptionParams
abstract type ArduinoGaussMeterParams <: DeviceParams end

Base.@kwdef struct ArduinoGaussMeterDirectParams <: ArduinoGaussMeterParams
  portAddress::String
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

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterDescriptionParams(dict::Dict) = params_from_dict(ArduinoGaussMeterDescriptionParams, dict)


Base.@kwdef mutable struct ArduinoGaussMeter <: GaussMeter
  @add_device_fields ArduinoGaussMeterParams
  ard::Union{SimpleArduino, Nothing} = nothing
end

neededDependencies(::ArduinoGaussMeter) = []
optionalDependencies(::ArduinoGaussMeter) = [SerialPortPool]

function _init(gauss::ArduinoGaussMeter)
  params = gauss.params
  sd = initSerialDevice(gauss, params)
  @info "Connection to ArduinoGaussMeter established."        
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, sd = sd)
  gauss.ard = ard
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
  data_strings = split(sendCommand(gauss.ard, "DATA"), ",")
  data = [parse(Float32,str) for str in data_strings]
  return data
end
export setSampleSize
function setSampleSize(gauss::ArduinoGaussMeter, samplesize::Int)
  data_string = sendCommand(gauss.ard, "SAMPLES" * string(samplesize))
  return parse(Int, data_string)
end

export getTemperature
function getTemperature(gauss::ArduinoGaussMeter)
  temp_str = sendCommand(gauss.ard, "TEMP")
  return parse(Float32,temp_str)
end

close(gauss::ArduinoGaussMeter) = close(gauss.ard)