mutable struct DAQParams
  decimation::Int64
  dfBaseFrequency::Float64
  dfDivider::Vector{Int64}
  dfFreq::Vector{Float64}
  dfStrength::Vector{Float64}
  dfPhase::Vector{Float64}
  dfCycle::Float64
  dfWaveform::String
  jumpSharpness::Float64
  rxBandwidth::Float64
  acqNumPeriodsPerFrame::Int64
  numSampPerPeriod::Int64
  rxNumSamplingPoints::Int64
  acqNumFrames::Int64
  acqNumBGFrames::Int64
  acqFramePeriod::Float64
  acqNumAverages::Int64
  acqNumFrameAverages::Int64
  acqNumSubperiods::Int64
  acqNumPeriodsPerPatch::Int64
  sinLUT::Matrix{Float64}
  cosLUT::Matrix{Float64}
  acqNumFFChannels::Int64
  acqFFValues::Matrix{Float64}
  acqEnableSequence::Matrix{Bool}
  calibIntToVolt::Matrix{Float64}
  calibRefToField::Vector{Float64}
  calibFieldToVolt::Vector{Float64}
  calibFFCurrentToVolt::Vector{Float64}
  currTx::Matrix{ComplexF64}
  controlPause::Float64
  controlLoopAmplitudeAccuracy::Float64
  controlLoopPhaseAccuracy::Float64
  correctCrossCoupling::Bool
  rxChanIdx::Vector{Int64}
  refChanIdx::Vector{Int64}
  dfChanIdx::Vector{Int64}
  txLimitVolt::Vector{Float64}
  txOffsetVolt::Vector{Float64}
  controlPhase::Bool
  acqFFSequence::String
  ffRampUpTime::Float64
  ffRampUpFraction::Float64
  triggerMode::String
  passPDMToFastDAC::Vector{Bool}
end

function calcDFFreq(baseFreq::Float64, divider::Vector{Int64})
  return baseFreq ./ divider
end

function DAQParams(@nospecialize params_)

  params = deepcopy(params_) # We do not want to change the user parameter!

  D = length(params["dfDivider"])
  #dfFreq = params["dfBaseFrequency"] ./ params["dfDivider"]
  dfFreq = calcDFFreq(params["dfBaseFrequency"],params["dfDivider"])
  dfCycle = lcm(params["dfDivider"]) / params["dfBaseFrequency"]

  if !all(isinteger, params["dfDivider"] / params["decimation"])
    warn("$(params["dfDivider"]) cannot be divided by $(params["decimation"])")
  end
  numSampPerPeriod = round(Int, lcm(params["dfDivider"]) / params["decimation"])

  rxBandwidth = params["dfBaseFrequency"] / params["decimation"] / 2

  sinLUT, cosLUT = initLUT(numSampPerPeriod, D, dfCycle, dfFreq)

  if !haskey(params, "currTx")
    params["currTx"] = convert(Matrix{ComplexF64}, diagm(params["txLimitVolt"] / 10))
  end

  if !haskey(params, "txOffsetVolt")
    params["txOffsetVolt"] = zeros(length(params["txLimitVolt"]))
  end

  if !haskey(params, "controlPhase")
    params["controlPhase"] = true
  end

  if !haskey(params, "correctCrossCoupling")
    params["correctCrossCoupling"] = false
  end

  if !haskey(params, "dfWaveform")
    params["dfWaveform"] = "SINE"
  end  

  if !haskey(params,"acqFFSequence")
    params["acqFFSequence"] = "None"
  end
  if params["acqFFSequence"] != ""

    s = Sequence(params["acqFFSequence"])

    params["acqFFValues"] = s.values 
    params["acqNumFFChannels"] = size(params["acqFFValues"],1)
    params["acqNumPeriodsPerFrame"] = acqNumPeriodsPerFrame(s)
    params["acqNumPeriodsPerPatch"] = acqNumPeriodsPerPatch(s)
    params["acqEnableSequence"] = s.enable
  else
    params["acqFFValues"] = zeros(0,0)
    params["acqNumFFChannels"] = 1
    params["acqNumPeriodsPerFrame"] = 1
    params["acqEnableSequence"] = zeros(Bool,0,0)
  end

  acqFramePeriod = dfCycle * params["acqNumPeriodsPerFrame"]

  if !haskey(params,"calibFFCurrentToVolt")
    params["calibFFCurrentToVolt"] = [0.0]
  end


  if !haskey(params,"acqNumSubperiods")
    params["acqNumSubperiods"] = 1
  end

  if !haskey(params,"acqNumPeriodsPerPatch")
    params["acqNumPeriodsPerPatch"] = 1
  end

  if !haskey(params,"ffRampUpTime")
    params["ffRampUpTime"] = 0.4
  end

  if !haskey(params,"ffRampUpFraction")
    params["ffRampUpFraction"] = 0.8
  end

  if !haskey(params,"acqNumFrameAverages")
    params["acqNumFrameAverages"] = 1
  end

  if !haskey(params,"acqNumBGFrames")
    params["acqNumBGFrames"] = 1
  end

  if !haskey(params,"triggerMode")
    params["triggerMode"] = "EXTERNAL"
  end

  if !haskey(params,"jumpSharpness")
    params["jumpSharpness"] = 0.0
  end

  if !haskey(params,"passPDMToFastDAC")
    params["passPDMToFastDAC"] = zeros(Bool,10) # how many RP have we???
  end

  params = DAQParams(
    params["decimation"],
    params["dfBaseFrequency"],
    params["dfDivider"],
    dfFreq,
    params["dfStrength"],
    params["dfPhase"],
    dfCycle,
    params["dfWaveform"],
    params["jumpSharpness"],
    rxBandwidth,
    params["acqNumPeriodsPerFrame"],
    numSampPerPeriod,
    numSampPerPeriod*params["acqNumSubperiods"],
    params["acqNumFrames"],
    params["acqNumBGFrames"],
    acqFramePeriod,
    params["acqNumAverages"],
    params["acqNumFrameAverages"],
    params["acqNumSubperiods"],
    params["acqNumPeriodsPerPatch"],
    sinLUT,
    cosLUT,
    params["acqNumFFChannels"],
    reshape(params["acqFFValues"],params["acqNumFFChannels"],:),
    reshape(params["acqEnableSequence"],params["acqNumFFChannels"],:),
    reshape(params["calibIntToVolt"],2,:),
    params["calibRefToField"],
    params["calibFieldToVolt"],
    params["calibFFCurrentToVolt"],
    params["currTx"],
    params["controlPause"],
    params["controlLoopAmplitudeAccuracy"],
    params["controlLoopPhaseAccuracy"],
    params["correctCrossCoupling"],
    params["rxChanIdx"],
    params["refChanIdx"],
    params["dfChanIdx"],
    params["txLimitVolt"],
    params["txOffsetVolt"],
    params["controlPhase"],
    params["acqFFSequence"],
    params["ffRampUpTime"],
    params["ffRampUpFraction"],
    params["triggerMode"],
    params["passPDMToFastDAC"]
   )

  return params
end

function MPIFiles.toDict(p::DAQParams)
  params= Dict{String,Any}()

  params["decimation"] = p.decimation
  params["dfBaseFrequency"] = p.dfBaseFrequency
  params["dfDivider"] = p.dfDivider
  params["dfFreq"] = p.dfFreq
  params["dfStrength"] = p.dfStrength
  params["dfPhase"] = p.dfPhase
  params["dfCycle"] = p.dfCycle
  params["dfWaveform"] = p.dfWaveform
  params["jumpSharpness"] = p.jumpSharpness
  params["rxBandwidth"] = p.rxBandwidth
  params["acqNumPeriodsPerFrame"] = p.acqNumPeriodsPerFrame
  params["numSampPerPeriod"] = p.numSampPerPeriod
  params["rxNumSamplingPoints"] = p.rxNumSamplingPoints
  params["acqNumFrames"] = p.acqNumFrames
  params["acqNumBGFrames"] = p.acqNumBGFrames
  params["acqNumSubperiods"] = p.acqNumSubperiods
  params["acqNumPeriodsPerPatch"] = p.acqNumPeriodsPerPatch
  params["acqFramePeriod"] = p.acqFramePeriod
  params["acqNumAverages"] = p.acqNumAverages
  params["acqNumFrameAverages"] = p.acqNumFrameAverages
  params["acqNumFFChannels"] = p.acqNumFFChannels
  params["acqFFValues"] = p.acqFFValues
  params["acqEnableSequence"] = p.acqEnableSequence
  params["calibIntToVolt"] = vec(p.calibIntToVolt)
  params["calibRefToField"] = p.calibRefToField
  params["calibFFCurrentToVolt"] = p.calibFFCurrentToVolt
  params["currTx"] = p.currTx
  params["controlPause"] = p.controlPause
  params["controlLoopAmplitudeAccuracy"] = p.controlLoopAmplitudeAccuracy
  params["controlLoopPhaseAccuracy"] = p.controlLoopPhaseAccuracy
  params["correctCrossCoupling"] = p.correctCrossCoupling
  params["calibFieldToVolt"] = p.calibFieldToVolt
  params["rxChanIdx"] = p.rxChanIdx
  params["refChanIdx"] = p.refChanIdx
  params["dfChanIdx"] = p.dfChanIdx
  params["txLimitVolt"] = p.txLimitVolt
  params["txOffsetVolt"] = p.txOffsetVolt
  params["controlPhase"] = p.controlPhase
  params["acqFFSequence"] = p.acqFFSequence
  params["ffRampUpTime"] = p.ffRampUpTime
  params["ffRampUpFraction"] = p.ffRampUpFraction
  params["triggerMode"] = p.triggerMode
  params["passPDMToFastDAC"] = p.passPDMToFastDAC

  return params
end
