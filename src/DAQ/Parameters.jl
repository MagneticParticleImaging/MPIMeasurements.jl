export toDict

type DAQParams
  decimation::Int64
  dfBaseFrequency::Float64
  dfDivider::Vector{Int64}
  dfFreq::Vector{Float64}
  dfStrength::Vector{Float64}
  dfPhase::Vector{Float64}
  dfPeriod::Float64
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
end


function DAQParams(params)

  dfFreq = params["dfBaseFrequency"] ./ params["dfDivider"]
  dfPeriod = lcm(params["dfDivider"]) / params["dfBaseFrequency"]

  if !all(isinteger, params["dfDivider"] / params["decimation"])
    warn("$(daq["dfDivider"]) cannot be divided by $(daq["decimation"])")
  end
  numSampPerPeriod = round(Int, lcm(params["dfDivider"]) / params["decimation"])

  rxBandwidth = params["dfBaseFrequency"] / params["decimation"] / 2

  acqFramePeriod = dfPeriod * params["acqNumPeriodsPerFrame"]

  sinLUT, cosLUT = initLUT(numSampPerPeriod, length(params["dfDivider"]), dfPeriod, dfFreq)

  D = length(params["dfDivider"])

  params = DAQParams(
    params["decimation"],
    params["dfBaseFrequency"],
    params["dfDivider"],
    dfFreq,
    params["dfStrength"],
    params["dfPhase"],
    dfPeriod,
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
    reshape(params["calibIntToVolt"],4,:),
    params["calibRefToField"],
    params["calibFieldToVolt"],
    params["currTxAmp"],
    params["currTxPhase"],
    params["controlPause"],
    params["controlLoopAmplitudeAccuracy"],
    params["controlLoopPhaseAccuracy"]
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
  params["dfPeriod"] = p.dfPeriod
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

  return params
end
