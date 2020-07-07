mutable struct DAQParams
  decimation::Int64
  dfBaseFrequency::Float64
  dfDivider::Vector{Int64}
  dfFreq::Vector{Float64}
  dfStrength::Vector{Float64}
  dfPhase::Vector{Float64}
  dfCycle::Float64
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
  acqFFLinear::Bool
  calibIntToVolt::Matrix{Float64}
  calibRefToField::Vector{Float64}
  calibFieldToVolt::Vector{Float64}
  calibFFCurrentToVolt::Vector{Float64}
  currTxAmp::Vector{Float64}
  currTxPhase::Vector{Float64}
  controlPause::Float64
  controlLoopAmplitudeAccuracy::Float64
  controlLoopPhaseAccuracy::Float64
  rxChanIdx::Vector{Int64}
  refChanIdx::Vector{Int64}
  dfChanIdx::Vector{Int64}
  rpModulus::Vector{Int64}
  dfChanToModulusIdx::Vector{Int64} #RP specific
  txLimitVolt::Vector{Float64}
  controlPhase::Bool
  acqFFSequence::String
  ffRampUpTime::Float64
  ffRampUpFraction::Float64
  triggerMode::String
end

function calcDFFreq(baseFreq::Float64, divider::Vector{Int64})
  return baseFreq ./ divider
end

function DAQParams(@nospecialize params)

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

  dfChanToModulusIdx = [findfirst_(params["rpModulus"], c) for c in params["dfDivider"]]

  if !haskey(params, "currTxAmp")
    params["currTxAmp"] = params["txLimitVolt"] / 10
  end
  if !haskey(params, "currTxPhase")
    params["currTxPhase"] = zeros(D)
  end
  if !haskey(params, "controlPhase")
    params["controlPhase"] = true
  end

  if !haskey(params,"acqFFSequence")
    params["acqFFSequence"] = "None"
  end
  if params["acqFFSequence"] != "None"
    params["acqFFValues"] = readdlm(joinpath(@__DIR__,"..","Sequences",
                                    params["acqFFSequence"]*".csv"),',')
    params["acqNumFFChannels"] = size(params["acqFFValues"],1)
    #params["acqNumPeriodsPerFrame"] = size(params["acqFFValues"],2)

    params["acqNumPeriodsPerPatch"] = div(params["acqNumPeriodsPerFrame"], size(params["acqFFValues"],2))
  else
    params["acqFFValues"] = zeros(0,0)
    params["acqNumFFChannels"] = 1
    params["acqNumPeriodsPerFrame"] = 1
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

  params = DAQParams(
    params["decimation"],
    params["dfBaseFrequency"],
    params["dfDivider"],
    dfFreq,
    params["dfStrength"],
    params["dfPhase"],
    dfCycle,
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
    params["acqFFLinear"],
    reshape(params["calibIntToVolt"],2,:),
    params["calibRefToField"],
    params["calibFieldToVolt"],
    params["calibFFCurrentToVolt"],
    params["currTxAmp"],
    params["currTxPhase"],
    params["controlPause"],
    params["controlLoopAmplitudeAccuracy"],
    params["controlLoopPhaseAccuracy"],
    params["rxChanIdx"],
    params["refChanIdx"],
    params["dfChanIdx"],
    params["rpModulus"],
    dfChanToModulusIdx,
    params["txLimitVolt"],
    params["controlPhase"],
    params["acqFFSequence"],
    params["ffRampUpTime"],
    params["ffRampUpFraction"],
    params["triggerMode"]
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
  params["acqFFLinear"] = p.acqFFLinear
  params["calibIntToVolt"] = vec(p.calibIntToVolt)
  params["calibRefToField"] = p.calibRefToField
  params["calibFFCurrentToVolt"] = p.calibFFCurrentToVolt
  params["currTxAmp"] = p.currTxAmp
  params["currTxPhase"] = p.currTxPhase
  params["controlPause"] = p.controlPause
  params["controlLoopAmplitudeAccuracy"] = p.controlLoopAmplitudeAccuracy
  params["controlLoopPhaseAccuracy"] = p.controlLoopPhaseAccuracy
  params["calibFieldToVolt"] = p.calibFieldToVolt
  params["rxChanIdx"] = p.rxChanIdx
  params["refChanIdx"] = p.refChanIdx
  params["dfChanIdx"] = p.dfChanIdx
  params["rpModulus"] = p.rpModulus
  params["txLimitVolt"] = p.txLimitVolt
  params["controlPhase"] = p.controlPhase
  params["acqFFSequence"] = p.acqFFSequence
  params["ffRampUpTime"] = p.ffRampUpTime
  params["ffRampUpFraction"] = p.ffRampUpFraction
  params["triggerMode"] = p.triggerMode

  return params
end
