export DAQSimulation

type DAQSimulation <: AbstractDAQ
  params::Dict
end

function DAQSimulation(params)
  daq = DAQSimulation(params)
  init(daq)
  return daq
end

currentFrame(daq::DAQSimulation) = 1

function startTx(daq::DAQSimulation)
  dfAmplitude = daq["dfStrength"][1]
  dec = daq["decimation"]
  freq = daq["dfFreq"][1]

  # start sending
  send(daq.rp,"GEN:RST")
  sendAnalogSignal(daq.rp,1,"SINE",freq,
                   daq["calibFieldToVolt"]*dfAmplitude)
end

function stopTx(daq::DAQSimulation)
  #Redpitaya.disableAnalogOutput(daq.rp,1)
end

function setTxParams(daq::DAQSimulation, amplitude, phase)
  if amplitude[1] < 0.5
    @info "SOUR1:VOLT $(amplitude[1])"
    send(daq.rp,"SOUR1:VOLT $(amplitude[1])") # Set amplitude of output signal
  else
    error("errorororo")
  end
end

refToField(daq::DAQSimulation) = daq["calibRefToField"]

function readData(daq::DAQSimulation, numFrames, startFrame=1)



  dec = daq["decimation"]
  numSampPerPeriod = daq["numSampPerPeriod"]
  numSamp = numSampPerPeriod*numFrames

  sleep(0.1)

  trigger = "NOW" #"AWG_NE" # or NOW

  uMeas, uRef = receiveAnalogSignalWithTrigger(daq.rp, 0, 0, numSamp, dec=dec, delay=0.01,
                typ="OLD", trigger=trigger, triggerLevel=-0.0,
                binary=true, triggerDelay=numSampPerPeriod)

  phase = phaseShift(uRef, numFrames)

  uMeas[:] = circshift(uMeas, -phase)
  uRef[:] = circshift(uRef,-phase)

  return reshape(uMeas,numSampPerPeriod,1,1,numFrames), reshape(uRef,numSampPerPeriod,1,1,numFrames)
end
