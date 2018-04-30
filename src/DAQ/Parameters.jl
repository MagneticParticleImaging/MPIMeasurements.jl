export toDict

type DAQParams
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
  acqNumFrames::Int64
  acqFramePeriod::Float64
  acqNumAverages::Int64
  sinLUT::Matrix{Float64}
  cosLUT::Matrix{Float64}
  acqNumFFChannels::Int64
  acqFFValues::Matrix{Float64}
  acqFFLinear::Bool
  calibIntToVolt::Matrix{Float64}
  calibRefToField::Vector{Float64}
  calibFieldToVolt::Vector{Float64}
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
end


function DAQParams(params)

  D = length(params["dfDivider"])
  dfFreq = params["dfBaseFrequency"] ./ params["dfDivider"]
  dfCycle = lcm(params["dfDivider"]) / params["dfBaseFrequency"]

  if !all(isinteger, params["dfDivider"] / params["decimation"])
    warn("$(daq["dfDivider"]) cannot be divided by $(daq["decimation"])")
  end
  numSampPerPeriod = round(Int, lcm(params["dfDivider"]) / params["decimation"])

  rxBandwidth = params["dfBaseFrequency"] / params["decimation"] / 2

  acqFramePeriod = dfCycle * params["acqNumPeriodsPerFrame"]

  sinLUT, cosLUT = initLUT(numSampPerPeriod, D, dfCycle, dfFreq)

  dfChanToModulusIdx = [findfirst(params["rpModulus"], c) for c in params["dfDivider"]]

  if !haskey(params, "currTxAmp")
    params["currTxAmp"] = params["txLimitVolt"] ./ 10
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
  params["acqFFValues"] = readcsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                    params["acqFFSequence"]*".csv"))
  params["acqNumFFChannels"] = size(params["acqFFValues"],1)
  params["acqNumPeriodsPerFrame"] = size(params["acqFFValues"],2)

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
    params["acqNumFrames"],
    acqFramePeriod,
    params["acqNumAverages"],
    sinLUT,
    cosLUT,
    params["acqNumFFChannels"],
    reshape(params["acqFFValues"],:,params["acqNumFFChannels"]),
    params["acqFFLinear"],
    reshape(params["calibIntToVolt"],2,:),
    params["calibRefToField"],
    params["calibFieldToVolt"],
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
    params["acqFFSequence"]
   )

  return params
end

function toDict(p::DAQParams)
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
  params["acqNumFrames"] = p.acqNumFrames
  params["acqFramePeriod"] = p.acqFramePeriod
  params["acqNumAverages"] = p.acqNumAverages
  params["acqNumFFChannels"] = p.acqNumFFChannels
  params["acqFFValues"] = p.acqFFValues
  params["acqFFLinear"] = p.acqFFLinear
  params["calibIntToVolt"] = vec(p.calibIntToVolt)
  params["calibRefToField"] = p.calibRefToField
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

  return params
end
