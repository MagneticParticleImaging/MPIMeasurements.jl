using LinearAlgebra

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
  "Coordinate transformation matrix"
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
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
  # Expand tilde in path
  sensorFolder = expanduser(params.sensorFolder)
  cam.sensorFolder = sensorFolder
  
  # Try to load student code for sensor positions and advanced functions
  # Only load serialCommunicationDeviceArduino.jl (skip messungSensorarray.jl which has dependencies)
  serialFile = joinpath(sensorFolder, "serialCommunicationDeviceArduino.jl")
  
  if isfile(serialFile)
    try
      cd(sensorFolder) do
        # Load in a way that avoids type conflicts
        Main.eval(:(
          begin
            # Prevent Device type conflict by checking if already defined
            if !@isdefined(Device)
              abstract type Device end
            end
            include($serialFile)
          end
        ))
      end
      @info "Student sensor positions loaded from serialCommunicationDeviceArduino.jl"
    catch e
      @info "Student code not loaded (positions will not be saved): $(sprint(showerror, e))"
    end
  end

  # Use the student's serial device if available, otherwise create our own
  try
    if isdefined(Main, :mySphericalSensor) && hasfield(typeof(Main.mySphericalSensor), :sd)
      cam.sd = Main.mySphericalSensor.sd
      @info "Using student's serial device at $(params.portAddress)"
    else
      sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
      cam.sd = sd
      @info "Field camera serial connected at $(params.portAddress)"
    end
  catch e
    @warn "Could not open serial device: $e"
  end

  # Initialize sensors to desired range
  initializeSensors = try
    # The student's code defines initializeSensors! or similar; if present use it
    isdefined(@__MODULE__, :initializeSensors!)
  catch
    false
  end

  # Try to initialize using our local helper if available
  #try
  #  # Prefer the adapter's initializeSensors! if defined in included file
  #  if @isdefined initializeSensors! && typeof(initializeSensors!) <: Function
  #    # call as needed later via acquireFullField
  #    nothing
  #  end
  #catch
  #  nothing
  #end

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
    if isdefined(Main, :saveAllValuesArduino) && typeof(Main.saveAllValuesArduino) <: Function
      try
        # Use input string for display name (e.g., "150") and second arg 0 as in messungSensorarray.jl
        displayStr = string(cam.params.measurementRange)
        res = Main.saveAllValuesArduino(displayStr, 0)
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
    if isdefined(Main, :query) && typeof(Main.query) <: Function && !isnothing(cam.sd)
      data = zeros(typeof(1.0u"T"), 3, numSensors)
      crcErrorCount = 0
      # Attempt to reuse sensor pin order from student's file if available
      sensorPins = try
        isdefined(Main, :sensors) ? Main.sensors : nothing
      catch
        nothing
      end
      if sensorPins === nothing
        # Default ascending pins 1..numSensors
        sensorPins = collect(1:numSensors)
      end
      for (idx, pin) in enumerate(sensorPins)
        # Select the chip first
        pinHex = string(pin, base=16)
        selectCmd = "*SELECTCHIP!>0x$(pinHex)#"
        # Query the field values
        queryCmd = "*GETFIELDVALUEXYZ?#"
        
        try
          # Select sensor
          selectResp = Main.query(cam.sd, selectCmd)
          if isnothing(selectResp) || occursin("ERROR", uppercase(string(selectResp)))
            @debug "Failed to select pin $pin: $selectResp"
            continue
          end
          
          # Read field values
          resp = Main.query(cam.sd, queryCmd)
          respStr = strip(string(resp))
          
          # Check for CRC errors
          if occursin("CRC ERROR", respStr)
            crcErrorCount += 1
            data[:, idx] .= 0.0u"mT"
          elseif !occursin("ERROR", respStr)
            # Parse format: *X<Y>Z#
            m = match(r"\*([^<]+)<([^>]+)>([^#]+)#", respStr)
            if !isnothing(m)
              data[1, idx] = parse(Float64, m.captures[1]) * 1u"mT"
              data[2, idx] = parse(Float64, m.captures[2]) * 1u"mT"
              data[3, idx] = parse(Float64, m.captures[3]) * 1u"mT"
            else
              @debug "Could not parse response for pin $pin: $resp"
            end
          else
            @debug "Bad response for pin $pin: $resp"
          end
        catch e
          @debug "Error querying pin $pin: $e"
        end
      end
      
      # Summary warning if many CRC errors occurred
      if crcErrorCount > 0
        @warn "CRC errors occurred for $crcErrorCount sensors ($(round(crcErrorCount/length(sensors)*100, digits=1))%)"
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
function getXYZValues(cam::FieldCameraAdapter)
  r = acquireFullField(cam)
  return [mean(r.data[1, :]), mean(r.data[2, :]), mean(r.data[3, :])]
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

function enable(gauss::FieldCameraAdapter)
  lock(gauss.lock) do
    disable(gauss)
    gauss.ch = Channel{FieldCameraResult}(gauss.params.bufferSize)
    gauss.task = Threads.@spawn readData(gauss)
    bind(gauss.ch, gauss.task)
  end
end

function disable(gauss::FieldCameraAdapter)
  lock(gauss.lock) do
    try
      if !isnothing(gauss.task) && !istaskdone(gauss.task)
        close(gauss.ch)
        # Give task time to finish
        for i in 1:10
          istaskdone(gauss.task) && break
          sleep(0.1)
        end
      end
    catch e
      @debug "Error disabling FieldCameraAdapter: $e"
    end 
  end
end
