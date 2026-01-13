export ArduinoFieldCamera, ArduinoFieldCameraParams, ArduinoFieldCameraDirectParams
export ArduinoFieldCameraResult, FieldCameraData

"""
Parameters for the Arduino-based field camera (spherical sensor array)
"""
abstract type ArduinoFieldCameraParams <: DeviceParams end

Base.@kwdef struct ArduinoFieldCameraDirectParams <: ArduinoFieldCameraParams
  "Serial port address (e.g., COM3 or /dev/ttyUSB0)"
  portAddress::String
  "Buffer size for data acquisition"
  bufferSize::Int64 = 2048
  "Number of sensors in the array"
  numSensors::Int64 = 37
  "Radius of the spherical sensor array in meters"
  radius::typeof(1.0u"m") = 0.037u"m"
  "T-Design order"
  tDesign::Int64 = 8
  "Calibration file path for coordinate transformation"
  calibrationFile::String = ""
  "Measurement range in mT (150, 75, or 300)"
  measurementRange::Int64 = 150
  @add_serial_device_fields "\r" 8 SP_PARITY_NONE
end
ArduinoFieldCameraDirectParams(dict::Dict) = params_from_dict(ArduinoFieldCameraDirectParams, dict)

"""
Result structure for a single field camera measurement
Contains timestamp and magnetic field data from all sensors
"""
struct ArduinoFieldCameraResult
  timestamp::Float64
  data::Matrix{typeof(1.0u"T")}  # 3 x numSensors matrix
end

"""
Structure for organizing field camera data with metadata
"""
struct FieldCameraData
  timestamp::Float64
  sensorData::Matrix{typeof(1.0u"T")}  # 3 x numSensors
  positions::Matrix{Float64}  # 3 x numSensors (positions in mm)
  range::Int64
end

"""
Arduino-based spherical field camera device implementing GaussMeter interface

This device wraps the spherical sensor array functionality from the student's
implementation (messungSensorarray.jl) into the MPIMeasurements framework.
It allows flexible field measurements that can be used alongside traditional
gauss meters.
"""
Base.@kwdef mutable struct ArduinoFieldCamera <: GaussMeter
  @add_device_fields ArduinoFieldCameraParams
  
  "Serial device connection"
  sd::Union{SerialDevice, Nothing} = nothing
  
  "Channel for streaming measurement data"
  ch::Channel{ArduinoFieldCameraResult} = Channel{ArduinoFieldCameraResult}(1)
  
  "Background task for data acquisition"
  task::Union{Nothing, Task} = nothing
  
  "Lock for thread-safe operations"
  lock::ReentrantLock = ReentrantLock()
  
  "Sensor positions in mm [X, Y, Z] x numSensors"
  sensorPositions::Matrix{Float64} = zeros(Float64, 3, 37)
  
  "Offset calibration for 300mT range [X, Y, Z] x numSensors"
  offset300::Matrix{Float64} = zeros(Float64, 3, 37)
  
  "Offset calibration for 150mT range [X, Y, Z] x numSensors"
  offset150::Matrix{Float64} = zeros(Float64, 3, 37)
  
  "Offset calibration for 75mT range [X, Y, Z] x numSensors"
  offset75::Matrix{Float64} = zeros(Float64, 3, 37)
  
  "Coordinate transformation matrices for each sensor"
  coordinateTransform::Array{Float64, 3} = zeros(Float64, 37, 3, 3)
  
  "Sensor pin assignments"
  sensorPins::Vector{Int} = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 34]
  
  "Sensors on lower hemisphere (need inversion)"
  sensorsLower::Vector{Int} = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 43, 44, 45, 46]
  
  "Currently initialized range"
  currentRange::Int64 = 0
end

neededDependencies(::ArduinoFieldCamera) = []
optionalDependencies(::ArduinoFieldCamera) = [SerialPortPool]

"""
Initialize the Arduino field camera device
"""
function _init(camera::ArduinoFieldCamera)
  params = camera.params
  
  # Initialize serial device
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  camera.sd = sd
  
  @info "Connection to Arduino Field Camera established on $(params.portAddress)"
  
  # Wait for connection to stabilize
  sleep(1)
  
  # Check device connection by querying unique ID
  checkSerialDevice(camera)
  
  # Load sensor positions
  loadSensorPositions!(camera)
  
  # Load calibration data
  loadCalibration!(camera)
  
  # Initialize sensors with specified range
  initializeSensors!(camera, params.measurementRange)
  
  @info "Arduino Field Camera initialized successfully"
end

"""
Check serial device connection by verifying unique device ID
"""
function checkSerialDevice(camera::ArduinoFieldCamera)
  try
    response = query(camera.sd, "\"*GETID!>#\"")
    if !isnothing(response) && occursin("SphericalSensor", string(response))
      @info "Device verified: $response"
    else
      @warn "Unexpected device response: $response"
    end
  catch e
    @error "Failed to verify device connection" exception=e
    throw(DeviceException("Arduino Field Camera verification failed"))
  end
end

"""
Load sensor positions (in mm) from predefined array
"""
function loadSensorPositions!(camera::ArduinoFieldCamera)
  # Positions from serialCommunicationDeviceArduino.jl
  posX = [23.17546, 1.64737, -1.64737, 11.3194, -10.5912, 9.01035, -18.77659, -9.01053, -27.39906, 
          -23.17546, -29.80074, -11.3294, -23.17546, -29.80074, -35.41345, -27.39906, -18.77659, 1.64737,
          -11.3294, -35.41345, -10.5912, -9.01053, 23.17546, 9.01053, 11.3294, 10.5912, 27.39906,
          35.41345, 29.80074, 35.41345, -1.64737, 18.77659, 29.80074, 18.77659, 10.5912, 27.39906, 0]
  
  posY = [-9.01053, -10.5912, -10.5912, -29.80074, -35.41345, -27.39906, -11.3294, -27.39906, -23.17546,
          -9.01053, -18.77659, -29.80074, 9.01053, 18.77659, -1.64737, 23.17546, 11.3294, 10.5912,
          29.80074, 1.64737, 35.41345, 27.39906, 9.01053, 27.39906, 29.80074, 35.41345, 23.17546,
          1.64737, 18.77659, -1.64737, 10.5912, 11.3294, -18.77659, -11.3294, -35.41345, -23.17546, 0]
  
  posZ = [-27.39906, -35.41345, 35.41345, 18.77659, 1.64737, -23.17546, -29.80074, 23.17546, 9.01053,
          27.39906, -11.3294, -18.77659, -27.39906, 11.3294, 10.5912, -9.01053, 29.80074, 35.41345,
          18.77659, -10.5912, -1.64737, -23.17546, 27.39906, 23.17546, -18.77659, 1.64737, 9.01053,
          10.5912, -11.3294, -10.5912, -35.41345, -29.80074, 11.3294, 29.80074, -1.64737, -9.01053, 0]
  
  camera.sensorPositions = vcat(posX', posY', posZ')
end

"""
Load calibration offsets and coordinate transformations
"""
function loadCalibration!(camera::ArduinoFieldCamera)
  # Offset data from serialCommunicationDeviceArduino.jl
  offsetX300 = [-0.14, -0.27, -0.11, -0.41, -0.18, -0.38, -0.26, -0.28, -0.27, -0.47,
                -0.23, -0.32, -0.37, -0.65, -0.44, -0.27, -0.50, -0.48, -0.19, -0.42,
                -0.36, -0.27, -0.29, -0.50, -0.45, -0.28, -0.13, -0.27, -0.42, -0.55,
                -0.46, -0.33, -0.25, -0.11, -0.02, -0.20, -0.29]
  
  offsetY300 = [-0.28, -0.26, -0.51, -0.41, -0.24, -0.25, -0.40, -0.04, 0.09, -0.42,  
                -0.47, -0.29, -0.29, -0.31, -0.52, -0.32, -0.40, -0.39, -0.56, -0.22,
                -0.34, -0.18, -0.58, -0.33, -0.52, -0.19, -0.14, -0.48, -0.36, -0.55,
                -0.41, -0.31, -0.28, -0.24, -0.30, 0.08, -0.45]
  
  offsetZ300 = [-0.52, -0.38, -0.33, -0.41, -0.38, -0.45, -0.27, -0.42, -0.19, -0.35,
                -0.25, -0.30, -0.30, -0.42, -0.29, -0.32, -0.31, -0.53, -0.68, -0.42,
                -0.42, -0.43, -0.39, -0.47, -0.50, -0.41, -0.24, -0.39, -0.47, -0.50,
                -0.35, -0.41, -0.30, -0.21, -0.31, -0.14, -0.33]
  
  camera.offset300 = vcat(offsetX300', offsetY300', offsetZ300')
  
  offsetX150 = [0.24, 0.06, 0.20, 0.03, 0.05, 0.00, 0.03, 0.04, -0.08, 0.03, 
                0.12, 0.08, -0.14, -0.20, 0.07, 0.10, -0.12, -0.02, 0.03, -0.08,
                0.02, 0.04, 0.16, 0.00, 0.04, 0.05, -0.01, 0.16, 0.04, 0.00,
                -0.03, -0.03, 0.10, 0.06, 0.22, -0.03, 0.03]
  
  offsetY150 = [0.06, 0.14, -0.18, 0.06, 0.06, 0.13, 0.02, 0.21, 0.34, -0.09,
                -0.01, 0.04, 0.02, 0.07, 0.03, 0.03, 0.02, 0.14, 0.07, 0.08,
                0.01, 0.12, -0.17, 0.09, 0.00, 0.11, 0.02, -0.11, 0.08, -0.03,
                -0.01, -0.01, 0.10, 0.07, 0.01, 0.16, -0.14]
  
  offsetZ150 = [-0.21, 0.01, 0.02, -0.03, -0.01, -0.06, 0.02, -0.11, -0.03, 0.10,
                0.02, 0.02, -0.01, 0.01, 0.01, 0.02, 0.04, -0.04, -0.08, -0.09,
                -0.02, -0.11, -0.01, -0.01, -0.04, -0.09, -0.07, -0.22, -0.06, -0.03,
                -0.01, -0.11, 0.02, -0.05, 0.02, -0.01, -0.02]
  
  camera.offset150 = vcat(offsetX150', offsetY150', offsetZ150')
  
  offsetX75 = [0.25, 0.11, 0.27, 0.04, 0.09, 0.01, 0.06, 0.05, -0.04, 0.09,
               0.15, 0.12, -0.14, -0.16, 0.01, 0.12, -0.08, 0.00, 0.05, -0.04,
               0.06, 0.09, 0.23, 0.05, 0.04, 0.08, 0.02, 0.21, 0.08, 0.05,
               0.05, 0.01, 0.15, 0.07, 0.24, 0.01, 0.06]
  
  offsetY75 = [0.14, 0.18, -0.13, 0.07, 0.12, 0.13, 0.05, 0.23, 0.37, -0.05,
               0.03, 0.08, 0.03, 0.11, -0.02, 0.06, 0.05, 0.16, 0.10, 0.10,
               0.04, 0.16, -0.15, 0.14, 0.06, 0.15, 0.07, -0.10, 0.12, -0.02,
               0.01, 0.02, 0.13, 0.09, 0.05, 0.20, -0.11]
  
  offsetZ75 = [-0.16, 0.05, 0.06, 0.00, 0.05, -0.03, 0.05, -0.08, 0.00, 0.15,   
               0.05, 0.05, 0.01, 0.05, 0.06, 0.04, 0.07, -0.01, -0.05, -0.07,
               0.01, -0.08, 0.03, 0.03, -0.01, -0.07, -0.05, 0.02, -0.03, 0.01,
               0.03, -0.07, 0.06, -0.03, 0.04, 0.03, 0.02]
  
  camera.offset75 = vcat(offsetX75', offsetY75', offsetZ75')
  
  # Load coordinate transformation if calibration file provided
  if !isempty(camera.params.calibrationFile) && isfile(camera.params.calibrationFile)
    loadCoordinateTransform!(camera)
  else
    # Identity transformation by default
    for i in 1:37
      camera.coordinateTransform[i, :, :] = Matrix{Float64}(I, 3, 3)
    end
  end
end

"""
Load coordinate transformation from calibration file
"""
function loadCoordinateTransform!(camera::ArduinoFieldCamera)
  # This can be extended to load from HDF5 or other formats
  @info "Loading coordinate transformation from $(camera.params.calibrationFile)"
  # Placeholder for calibration loading
  # For now, use identity
  for i in 1:camera.params.numSensors
    camera.coordinateTransform[i, :, :] = Matrix{Float64}(I, 3, 3)
  end
end

"""
Initialize sensors with specified range
"""
function initializeSensors!(camera::ArduinoFieldCamera, range::Int)
  @info "Initializing sensors with range: $(range)mT"
  
  # Convert range to register value
  rangeRegister = if range == 300
    0x0
  elseif range == 150
    0x1
  elseif range == 75
    0x2
  else
    @error "Invalid range: $range. Must be 75, 150, or 300 mT"
    throw(ArgumentError("Invalid measurement range"))
  end
  
  # Check if already initialized
  rangeHex = string(rangeRegister, base=16, pad=1)
  checkCmd = "\"*CHECKINIT!>0x$(rangeHex)#\""
  response = query(camera.sd, checkCmd)
  
  if response != "F1"
    @info "Initializing sensors..."
    initCmd = "\"*INITALLSENSORS!>0x$(rangeHex)#\""
    response = query(camera.sd, initCmd)
    
    # Check for errors
    if occursin("F", string(response)) && response != "F1"
      @error "Sensor initialization failed: $response"
      throw(DeviceException("Sensor initialization error"))
    end
    @info "Sensors initialized"
  else
    @info "Sensors already initialized for range $(range)mT"
  end
  
  camera.currentRange = range
end

"""
Enable the field camera (start data acquisition)
"""
function enable(camera::ArduinoFieldCamera)
  lock(camera.lock) do
    if !isnothing(camera.task) && !istaskdone(camera.task)
      @warn "Field camera already enabled"
      return
    end
    
    @info "Enabling Arduino Field Camera data acquisition"
    camera.ch = Channel{ArduinoFieldCameraResult}(camera.params.bufferSize)
    camera.task = @async measurementLoop(camera)
  end
end

"""
Disable the field camera (stop data acquisition)
"""
function disable(camera::ArduinoFieldCamera)
  lock(camera.lock) do
    if isnothing(camera.task) || istaskdone(camera.task)
      @warn "Field camera already disabled"
      return
    end
    
    @info "Disabling Arduino Field Camera data acquisition"
    close(camera.ch)
    
    # Wait for task to finish
    wait(camera.task)
    camera.task = nothing
  end
end

"""
Main measurement loop that continuously acquires data from all sensors
"""
function measurementLoop(camera::ArduinoFieldCamera)
  try
    while isopen(camera.ch)
      # Get current timestamp
      timestamp = time()
      
      # Read all sensors
      sensorData = readAllSensors(camera)
      
      if !isnothing(sensorData)
        # Create result structure
        result = ArduinoFieldCameraResult(timestamp, sensorData)
        
        # Try to put data in channel (non-blocking)
        try
          put!(camera.ch, result)
        catch e
          if !isa(e, InvalidStateException)
            @error "Error putting data in channel" exception=e
          end
          break
        end
      end
      
      # Small delay to avoid overwhelming the serial port
      sleep(0.01)
    end
  catch e
    @error "Error in measurement loop" exception=e
  finally
    @info "Measurement loop terminated"
  end
end

"""
Read magnetic field data from all sensors
Returns 3 x numSensors matrix in Tesla
"""
function readAllSensors(camera::ArduinoFieldCamera)
  numSensors = camera.params.numSensors
  data = zeros(typeof(1.0u"T"), 3, numSensors)
  
  # Select appropriate offset based on current range
  offset = if camera.currentRange == 300
    camera.offset300
  elseif camera.currentRange == 150
    camera.offset150
  else
    camera.offset75
  end
  
  try
    for (idx, pin) in enumerate(camera.sensorPins)
      # Query sensor
      cmd = "\"*GETFIELDVALUEALLFROMCHIP!>$(pin)#\""
      response = query(camera.sd, cmd)
      
      if isnothing(response) || occursin("F", string(response))
        @warn "Error reading sensor $pin: $response"
        continue
      end
      
      # Parse response (format: "Bx,By,Bz" in mT)
      values = parse.(Float64, split(strip(string(response)), ','))
      
      if length(values) == 3
        # Apply offset correction and convert to Tesla
        data[1, idx] = (values[1] - offset[1, idx]) * 1u"mT"
        data[2, idx] = (values[2] - offset[2, idx]) * 1u"mT"
        data[3, idx] = (values[3] - offset[3, idx]) * 1u"mT"
        
        # Apply coordinate transformation
        data[:, idx] = camera.coordinateTransform[idx, :, :] * data[:, idx]
        
        # Invert for lower hemisphere sensors
        if pin in camera.sensorsLower
          data[:, idx] = -data[:, idx]
        end
      end
    end
    
    return data
  catch e
    @error "Error reading sensors" exception=e
    return nothing
  end
end

"""
Get X component of magnetic field (averaged over all sensors)
"""
function getXValue(camera::ArduinoFieldCamera)
  if isready(camera.ch)
    data = fetch(camera.ch).data
    return mean(data[1, :])
  else
    @warn "No data available"
    return 0.0u"T"
  end
end

"""
Get Y component of magnetic field (averaged over all sensors)
"""
function getYValue(camera::ArduinoFieldCamera)
  if isready(camera.ch)
    data = fetch(camera.ch).data
    return mean(data[2, :])
  else
    @warn "No data available"
    return 0.0u"T"
  end
end

"""
Get Z component of magnetic field (averaged over all sensors)
"""
function getZValue(camera::ArduinoFieldCamera)
  if isready(camera.ch)
    data = fetch(camera.ch).data
    return mean(data[3, :])
  else
    @warn "No data available"
    return 0.0u"T"
  end
end

"""
Get temperature (not supported by this device)
"""
function getTemperature(camera::ArduinoFieldCamera)
  return 0.0u"°C"
end

"""
Get frequency (not supported by this device)
"""
function getFrequency(camera::ArduinoFieldCamera)
  return 0.0u"Hz"
end

"""
Calculate field error (not implemented for multi-sensor array)
"""
function calculateFieldError(camera::ArduinoFieldCamera, magneticField::Vector{<:Unitful.BField})
  return 0.0u"T"
end

"""
Close the device connection
"""
function Base.close(camera::ArduinoFieldCamera)
  disable(camera)
  if !isnothing(camera.sd)
    close(camera.sd)
    camera.sd = nothing
  end
  @info "Arduino Field Camera closed"
end
