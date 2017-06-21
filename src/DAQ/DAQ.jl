using Graphics: @mustimplement

abstract AbstractDAQ


@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, amplitude, phase)
@mustimplement controlPhaseDone(daq::AbstractDAQ)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, startFrame, numPeriods)

include("Parameters.jl")
include("RedPitaya.jl")
include("RedPitayaScpi.jl")

function init(daq::AbstractDAQ)
  daq.params["dfFreq"] = div(daq.params["dfBaseFrequency"],daq.params["dfDivider"])
  daq.params["dfPeriod"] = 1/daq.params["dfFreq"] # TODO: make this generic
  daq.params["numSampPerPeriod"] = round(Int, daq.params["dfBaseFrequency"] /
                                              daq.params["decimation"] *daq.params["dfPeriod"])

  #freqR = roundFreq(mps.rp,dec,freq)
end

function measurement(daq::AbstractDAQ; params=Dict{String,Any}() )

  updateParams(daq, params)
  numAverages = daq.params["acqNumAverages"]
  numFrames = daq.params["acqNumFrames"]
  numSampPerPeriod = daq.params["numSampPerPeriod"]

  startTx(daq)

  while !controlPhaseDone(daq)
    sleep(1.0)
  end
  currFr = currentFrame(daq)

  buffer = zeros(Float32,numSampPerPeriod, numFrames)
  for n=1:numFrames
    uMeas = readData(daq, currFr, numAverages)
    uMeas = mean(uMeas,2)
    buffer[:,n] = uMeas
  end

  stopTx(daq)

  return buffer
end




# low level OLD: uses SCPI interface
function measurement(mps::MPS,params=Dict{String,Any}())
  updateParams(mps, params)

  nAverages = mps.params["acqNumAverages"]
  amplitude = mps.params["dfStrength"]

  dec = mps.params["decimation"]
  freq = div(mps.params["dfBaseFrequency"],mps.params["dfDivider"])

  numPeriods = mps.params["acqNumFrames"]
  freqR = roundFreq(mps.rp,dec,freq)
  numSampPerPeriod = numSamplesPerPeriod(mps.rp,dec,freqR)
  numSamp = numSampPerPeriod*numPeriods

  println("Frequency = $freqR Hz")
  println("Number Sampling Points per Period: $numSampPerPeriod")

  println("Amplitude = $(amplitude*1000) mT")
  # start sending
  send(mps.rp,"GEN:RST")
  sendAnalogSignal(mps.rp,1,"SINE",freqR,
                   mps.params["calibFieldToVolt"]*amplitude)
  sleep(0.3)
  buffer = zeros(Float32,numSamp)
  for n=1:nAverages
    trigger = "NOW" #"AWG_NE" # or NOW

    uMeas, uRef = receiveAnalogSignalWithTrigger(mps.rp, 0, 0, numSamp, dec=dec, delay=0.01,
                typ="OLD", trigger=trigger, triggerLevel=-0.0,
                binary=true, triggerDelay=numSampPerPeriod)

    uMeas[:] = circshift(uMeas,-phaseShift(uRef, numPeriods))

    #if (maximum(uRef)*mps.params[:calibRefToField] - amplitude)/amplitude > 0.01
    #  println("Field not reached!")
    #end

    buffer[:] .+= uMeas
  end
  buffer[:] ./= nAverages

  disableAnalogOutput(mps.rp,1)

  return reshape(buffer,numSampPerPeriod,numPeriods)
end
