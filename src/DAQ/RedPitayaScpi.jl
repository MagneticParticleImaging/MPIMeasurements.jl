export DAQRedPitayaScpi

type DAQRedPitayaScpi <: AbstractDAQ
  params::Dict
  rp::RedPitaya
end

function DAQRedPitayaScpi()
  params = defaultDAQParams()
  println(params["ip"])
  rp = RedPitaya(params["ip"][1])
  daq = DAQRedPitayaScpi(params,rp)
  loadParams(daq)
  init(daq)
  return daq
end

function configFile(daq::DAQRedPitayaScpi)
  return Pkg.dir("MPIMeasurements","src","DAQ","Configurations","RedPitayaScpi.ini")
end

currentFrame(daq::DAQRedPitayaScpi) = 1

function startTx(daq::DAQRedPitayaScpi)
  dfAmplitude = daq.params["dfStrength"][1]
  dec = daq.params["decimation"]
  freq = daq.params["dfFreq"][1]

  # start sending
  send(daq.rp,"GEN:RST")
  sendAnalogSignal(daq.rp,1,"SINE",freq,
                   daq.params["calibFieldToVolt"]*dfAmplitude)
end

function stopTx(daq::DAQRedPitayaScpi)
  Redpitaya.disableAnalogOutput(daq.rp,1)
end

function setTxParams(daq::DAQRedPitayaScpi, amplitude, phase)
  println("SOUR1:VOLT $(amplitude[1])")
  send(daq.rp,"SOUR1:VOLT $(amplitude[1])") # Set amplitude of output signal
end

refToField(daq::DAQRedPitayaScpi) = daq["calibRefToField"]

function readData(daq::DAQRedPitayaScpi, numFrames, startFrame=1)

  dec = daq["decimation"]
  numSampPerPeriod = daq["numSampPerPeriod"]
  numSamp = numSampPerPeriod*numFrames

  sleep(0.1)

  trigger = "NOW" #"AWG_NE" # or NOW

  uMeas, uRef = receiveAnalogSignalWithTrigger(daq.rp, 0, 0, numSamp, dec=dec, delay=0.01,
                typ="OLD", trigger=trigger, triggerLevel=-0.0,
                binary=true, triggerDelay=numSampPerPeriod)

  uMeas[:] = circshift(uMeas,-phaseShift(uRef, numFrames))
  uRef[:] = circshift(uRef,-phaseShift(uRef, numFrames))

  return reshape(uMeas,numSampPerPeriod,1,numFrames), reshape(uRef,numSampPerPeriod,1,numFrames)
end
