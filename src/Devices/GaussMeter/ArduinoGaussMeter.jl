export ArduinoGaussMeter, ArduinoGaussMeterParams, ArduinoGaussMeterDirectParams, ArduinoGaussMeterPoolParams
abstract type ArduinoGaussMeterParams <: DeviceParams end

Base.@kwdef struct ArduinoGaussMeterDirectParams <: ArduinoGaussMeterParams
  portAddress::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  commandStart::String = "!"
  commandEnd::String = "*"
  pause_ms::Int = 30
  timeout_ms::Int = 1000
  delim::String = "#"
  baudrate::Integer = 9600
  ndatabits::Integer = 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1
end
ArduinoGaussMeterDirectParams(dict::Dict) = params_from_dict(ArduinoGaussMeterDirectParams, dict)

Base.@kwdef struct ArduinoGaussMeterPoolParams <: ArduinoGaussMeterParams
  position::Int64
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  calibration::Vector{Float64} = [0.098, 0.098, 0.098]

  commandStart::String = "!"
  commandEnd::String = "*"
  pause_ms::Int = 30
  timeout_ms::Int = 1000
  delim::String = "#"
  baudrate::Integer = 115200
  ndatabits::Integer = 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1
end
ArduinoGaussMeterPoolParams(dict::Dict) = params_from_dict(ArduinoGaussMeterPoolParams, dict)

Base.@kwdef mutable struct ArduinoGaussMeter <: GaussMeter
  @add_device_fields ArduinoGaussMeterParams
  ard::Union{SimpleArduino, Nothing} = nothing
end

neededDependencies(::ArduinoGaussMeter) = []
optionalDependencies(::ArduinoGaussMeter) = [SerialPortPool]

function _init(gauss::ArduinoGaussMeter)
  params = gauss.params
  sp = initSerialPort(gauss, params)
  sd = SerialDevice(sp, params.pause_ms, params.timeout_ms, params.delim, params.delim)
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, delim = params.delim, sd = sd)
  gauss.ard = ard
end

function initSerialPort(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterDirectParams)
  spTU = SerialPort(params.portAddress)
  open(spTU)
  set_speed(spTU, params.baudrate)
  set_frame(spTU,ndatabits=params.ndatabits,parity=params.parity,nstopbits=params.nstopbits)
  flush(spTU)
  write(spTU, "!VERSION*#")
  response=readuntil(spTU, Vector{Char}(params.delim), params.timeout_ms);
  @info response
  if(!(startswith(response, "HALLSENS:1")) ) 
      close(spTU)
      throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
    else
      @info "Connection to ArduinoTempBox established."        
  end
  return spTU
end

function initSerialPort(gauss::ArduinoGaussMeter, params::ArduinoGaussMeterPoolParams)
  pool = nothing
  if hasDependency(gauss, SerialPortPool)
    pool = dependency(gauss, SerialPortPool)
    sp = getSerialPort(pool, "!VERSION*#", "HALLSENS:1:$(params.position)#", params.baudrate, ndatabits=params.ndatabits,parity=params.parity,nstopbits=params.nstopbits)
    if isnothing(sp)
      throw(ScannerConfigurationError("Device $(deviceID(gauss)) found no fitting serial port."))
    end
    return sp
  else
    throw(ScannerConfigurationError("Device $(deviceID(gauss)) requires a SerialPortPool dependency but has none."))
  end
end

function getXYZValues(gauss::ArduinoGaussMeter)
  data = Array{Int16}(undef, 3)
  sendCommand(gauss.ard, "DATA", data)
  #TODO
  return data
end

close(gauss::ArduinoGaussMeter) = close(gauss.ard)