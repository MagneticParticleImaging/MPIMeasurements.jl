export ArduinoGaussMeter, ArduinoGaussMeterParams, ArduinoGaussMeterDirectParams, ArduinoGaussMeterPoolParams, ArduinoGaussMeterDescriptionParams
abstract type ArduinoGaussMeterParams <: DeviceParams end

Base.@kwdef struct ArduinoGaussMeterDirectParams <: ArduinoGaussMeterParams
  portAddress::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  @add_serial_device_fields '#'
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterDirectParams(dict::Dict) = params_from_dict(ArduinoGaussMeterDirectParams, dict)

Base.@kwdef struct ArduinoGaussMeterPoolParams <: ArduinoGaussMeterParams
  position::Int64
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  @add_serial_device_fields '#'
  @add_arduino_fields "!" "*"
end
ArduinoGaussMeterPoolParams(dict::Dict) = params_from_dict(ArduinoGaussMeterPoolParams, dict)

Base.@kwdef struct ArduinoGaussMeterDescriptionParams <: ArduinoGaussMeterParams
  description::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  @add_serial_device_fields '#'
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
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, sd = sd)
  gauss.ard = ard
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterDirectParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  response = query(sd, "!VERSION*")
  @debug response
  if(!(startswith(response, "HALLSENS:1")) ) 
      close(sd)
      throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
    else
      @info "Connection to ArduinoTempBox established."        
  end
  return sd
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterPoolParams)
  pool = nothing
  if hasDependency(gauss, SerialPortPool)
    pool = dependency(gauss, SerialPortPool)
    sd = getSerialDevice(pool, "!VERSION*", "HALLSENS:1:$(params.position)"; serial_device_splatting(params)...)
    if isnothing(sd)
      throw(ScannerConfigurationError("Device $(deviceID(gauss)) found no fitting serial port."))
    end
    return sd
  else
    throw(ScannerConfigurationError("Device $(deviceID(gauss)) requires a SerialPortPool dependency but has none."))
  end
end

function initSerialDevice(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterDescriptionParams)
  pool = nothing
  if hasDependency(gauss, SerialPortPool)
    pool = dependency(gauss, SerialPortPool)
    sd = getSerialDevice(pool, params.description; serial_device_splatting(params)...)
    if isnothing(sd)
      throw(ScannerConfigurationError("Device $(deviceID(gauss)) found no fitting serial port."))
    end
    return sd
  else
    throw(ScannerConfigurationError("Device $(deviceID(gauss)) requires a SerialPortPool dependency but has none."))
  end
end

function getXYZValues(gauss::ArduinoGaussMeter)
  data = zeros(Int16, 3)
  sendCommand(gauss.ard, "DATA", data)
  #TODO
  return data
end

close(gauss::ArduinoGaussMeter) = close(gauss.ard)