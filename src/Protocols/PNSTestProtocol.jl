export PNSTestProtocol, PNSTestProtocolParams
"""
Parameters for the PNSTestProtocol
"""
Base.@kwdef mutable struct PNSTestProtocolParams <: ProtocolParams
  "Strings to print"
  testMeasurements::Vector{String} = ["Measurement1", "Measurement2", "Measurement3", "Measurement4", "Measurement5"]
  "Seconds to wait between measurements"
  waitTime::Float64 = 2.0
end
function PNSTestProtocolParams(dict::Dict, scanner::MPIScanner)
  params = params_from_dict(PNSTestProtocolParams, dict)
  return params
end
PNSTestProtocolParams(dict::Dict) = params_from_dict(PNSTestProtocolParams, dict)

Base.@kwdef mutable struct PNSTestProtocol <: Protocol
  @add_protocol_fields PNSTestProtocolParams

  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  stopped::Bool = false
  restored::Bool = false
  measuring::Bool = false
  currStep::Int = 0
end

function requiredDevices(protocol::PNSTestProtocol)
  result = []
  return result
end

function _init(protocol::PNSTestProtocol)
  if isnothing(protocol.params.testMeasurements)
    throw(IllegalStateException("Protocol requires test measurements"))
  end

  return nothing
end

function timeEstimate(protocol::PNSTestProtocol)
  est = "Unknown"
  return est
end

function enterExecute(protocol::PNSTestProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.measuring = true
end


function _execute(protocol::PNSTestProtocol)
  @debug "Measurement protocol started"

#   @async begin
    for testMeasurement in protocol.params.testMeasurements
      @info "Test measurement: $testMeasurement"
      # Simulate some work
      sleep(protocol.params.waitTime)
    end
#   end

  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function cleanup(protocol::PNSTestProtocol)

end

function stop(protocol::PNSTestProtocol)
    protocol.stopped = true
    protocol.restored = false
    protocol.measuring = false
    @info "Protocol stopped."
    if !protocol.cancelled && !protocol.finishAcknowledged
        put!(protocol.biChannel, OperationSuccessfulEvent("Protocol stopped successfully."))
    end
end

function resume(protocol::PNSTestProtocol)
  protocol.stopped = false
  protocol.restored = true
  # OperationSuccessfulEvent is put when it actually leaves the stop loop
end

function cancel(protocol::PNSTestProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropiate
  protocol.stopped = true # Set stop to reach a known/save state
end

function handleEvent(protocol::PNSTestProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel, ProgressEvent(protocol.systemMeasState.currPos, length(protocol.params.sequences), "Position", event))
end

function handleEvent(protocol::PNSTestProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURR"
    data = protocol.systemMeasState.currentSignal
  elseif event.message == "BG"
    sysObj = protocol.systemMeasState
    index = sysObj.currPos
    while index > 1 && !sysObj.measIsBGPos[index]
      index = index - 1
    end
    startIdx = sysObj.posToIdx[index]
    data = copy(sysObj.signals[:, :, :, startIdx:startIdx])
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end

function handleEvent(protocol::PNSTestProtocol, event::DatasetStoreStorageRequestEvent)
  if false
    # TODO this should be some sort of storage failure event
    put!(protocol.biChannel, IllegaleStateEvent("Calibration measurement is not done yet. Cannot save!"))
  else
    store = event.datastore
    scanner = protocol.scanner
    mdf = event.mdf
    data = protocol.systemMeasState.signals
    positions = protocol.systemMeasState.positions
    isBackgroundFrame = protocol.systemMeasState.measIsBGFrame
    temperatures = nothing
    if protocol.params.saveTemperatureData
      temperatures = protocol.systemMeasState.temperatures
    end
    drivefield = nothing
    if !isempty(protocol.systemMeasState.drivefield)
      drivefield = protocol.systemMeasState.drivefield
    end
    applied = nothing
    if !isempty(protocol.systemMeasState.applied)
      applied = protocol.systemMeasState.applied
    end
    filename = saveasMDF(store, scanner, protocol.params.sequences[1], data, positions, isBackgroundFrame, mdf; storeAsSystemMatrix=protocol.params.saveAsSystemMatrix, temperatures=temperatures, drivefield=drivefield, applied=applied)
    @show filename
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::PNSTestProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::PNSTestProtocol) = Interactive()
protocolMDFStudyUse(protocol::PNSTestProtocol) = UsingMDFStudy()