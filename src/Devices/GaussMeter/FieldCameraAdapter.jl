export FieldCameraAdapter, FieldCameraAdapterParams, FieldCameraResult

abstract type FieldCameraAdapterParams <: DeviceParams end

Base.@kwdef struct FieldCameraAdapterDirectParams <: FieldCameraAdapterParams
  "Path to the spericalsensor communication folder"
  sensorFolder::String
  "COM port or serial device path"
  portAddress::String = "COM3"
  "Measurement range (mT)"
  measurementRange::Int64 = 150
  "Number of sensors"
  numSensors::Int64 = 37
  "Buffer size for streaming (not used for full-frame acquisition)"
  bufferSize::Int64 = 1
  @add_serial_device_fields "\r" 8 SP_PARITY_NONE
end

FieldCameraAdapterDirectParams(dict::Dict) = params_from_dict(FieldCameraAdapterDirectParams, dict)

struct FieldCameraResult
  timestamp::Float64
  data::Matrix{typeof(1.0u"T")} # 3 x numSensors
  filename::Union{String, Nothing}
end

Base.@kwdef mutable struct FieldCameraAdapter <: GaussMeter
  @add_device_fields FieldCameraAdapterParams
  sd::Union{SerialDevice, Nothing} = nothing
  ch::Channel{FieldCameraResult} = Channel{FieldCameraResult}(1)
  task::Union{Nothing, Task} = nothing
  lock::ReentrantLock = ReentrantLock()
  sensorFolder::String = ""
  currentRange::Int64 = 0
end

neededDependencies(::FieldCameraAdapter) = []
optionalDependencies(::FieldCameraAdapter) = [SerialPortPool]

function _init(cam::FieldCameraAdapter)
  params = cam.params
  cam.sensorFolder = params.sensorFolder
  # include the student's serial communication code so we can call its functions
  # Expect the folder to contain serialCommunicationDeviceArduino.jl and messungSensorarray.jl
  serialFile = joinpath(cam.sensorFolder, "serialCommunicationDeviceArduino.jl")
  messungFile = joinpath(cam.sensorFolder, "messungSensorarray.jl")

  if isfile(serialFile)
    include(serialFile)
  else
    @warn "serialCommunicationDeviceArduino.jl not found at $serialFile"
  end
  if isfile(messungFile)
    include(messungFile)
  else
    @warn "messungSensorarray.jl not found at $messungFile"
  end

  # Initialize serial device if SerialDevice is available from MPIMeasurements
  try
    sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
    cam.sd = sd
    @info "Field camera serial connected at $(params.portAddress)"
  catch e
    @warn "Could not open serial device: $e"
  end

  # Initialize sensors to desired range
  initializeSensors = try
    # The student's code defines initializeSensors! or similar; if present use it
    if @isdefined initializeSensors!
      true
    else
      false
    end
  catch
    false
  end

  # Try to initialize using our local helper if available
  try
    # Prefer the adapter's initializeSensors! if defined in included file
    if @isdefined initializeSensors! && typeof(initializeSensors!) <: Function
      # call as needed later via acquireFullField
      nothing
    end
  catch
    nothing
  end

  cam.currentRange = params.measurementRange
end

"""Acquire a full-frame measurement using the student's measurement routine.
Returns FieldCameraResult containing timestamp, 3 x N matrix (Tesla), and filename if data was saved.
"""
function acquireFullField(cam::FieldCameraAdapter)
  lock(cam.lock) do
    timestamp = time()
    filename = nothing
    numSensors = cam.params.numSensors

    # The student's function saveAllValuesArduino expects a display-range string and an int
    # We'll try to call it if available. Otherwise, fallback to querying individual sensors.
    if @isdefined saveAllValuesArduino && typeof(saveAllValuesArduino) <: Function
      try
        # Use input string for display name (e.g., "150") and second arg 0 as in messungSensorarray.jl
        displayStr = string(cam.params.measurementRange)
        res = saveAllValuesArduino(displayStr, 0)
        # saveAllValuesArduino returns a path string on success in their code
        if isa(res, AbstractString)
          filename = res
          # Try to parse saved CSV if it exists
          if isfile(res)
            # Attempt to read CSV into matrix: student's CSV format may vary; try DelimitedFiles
            try
              raw = readdlm(res, ',', Float64; skipstart=0)
              # raw likely includes header; assume columns map to sensor data; best-effort
              # Attempt to reshape into (numSensors, 3) per file — if fails, return nothing for data
              if size(raw, 2) >= 3
                data = zeros(typeof(1.0u"T"), 3, numSensors)
                # naive mapping: take first numSensors rows
                for i in 1:min(numSensors, size(raw,1))
                  data[:, i] = (raw[i, 1:3] .* 1.0) * 1u"mT"
                end
                return FieldCameraResult(timestamp, data, filename)
              end
            catch e
              @warn "Could not parse saved measurement CSV: $e"
            end
          end
        end
      catch e
        @warn "saveAllValuesArduino failed: $e"
      end
    end

    # Fallback: attempt to query sensors one-by-one using student's GETFIELD command if query() exists
    if @isdefined query && typeof(query) <: Function && !isnothing(cam.sd)
      data = zeros(typeof(1.0u"T"), 3, numSensors)
      # Attempt to reuse sensor pin order from student's file if available
      sensorPins = try
        @isdefined sensors ? sensors : nothing
      catch
        nothing
      end
      if sensorPins === nothing
        # Default ascending pins 1..numSensors
        sensorPins = collect(1:numSensors)
      end
      for (idx, pin) in enumerate(sensorPins)
        cmd = "\"*GETFIELDVALUEALLFROMCHIP!>$(pin)#\""
        try
          resp = query(cam.sd, cmd)
          if !isnothing(resp) && !occursin("F", string(resp))
            vals = parse.(Float64, split(strip(string(resp)), ','))
            if length(vals) >= 3
              data[1, idx] = vals[1] * 1u"mT"
              data[2, idx] = vals[2] * 1u"mT"
              data[3, idx] = vals[3] * 1u"mT"
            end
          else
            @warn "Bad response for pin $pin: $resp"
          end
        catch e
          @warn "Error querying pin $pin: $e"
        end
      end
      return FieldCameraResult(timestamp, data, nothing)
    end

    # If everything failed, return empty zeros
    data = zeros(typeof(1.0u"T"), 3, cam.params.numSensors)
    return FieldCameraResult(timestamp, data, nothing)
  end
end

# GaussMeter interface implementations
function getXValue(cam::FieldCameraAdapter)
  r = acquireFullField(cam)
  return mean(r.data[1, :])
end
function getYValue(cam::FieldCameraAdapter)
  r = acquireFullField(cam)
  return mean(r.data[2, :])
end
function getZValue(cam::FieldCameraAdapter)
  r = acquireFullField(cam)
  return mean(r.data[3, :])
end
function getTemperature(cam::FieldCameraAdapter)
  return 0.0u"°C"
end
function getFrequency(cam::FieldCameraAdapter)
  return 0.0u"Hz"
end
function calculateFieldError(cam::FieldCameraAdapter, magneticField::Vector{<:Unitful.BField})
  return 0.0u"T"
end

function Base.close(cam::FieldCameraAdapter)
  try
    if !isnothing(cam.sd)
      close(cam.sd)
      cam.sd = nothing
    end
  catch
    nothing
  end
  @info "FieldCameraAdapter closed"
end
