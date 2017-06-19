export DAQRedPitayaScpi

type DAQRedPitayaScpi <: AbstractDAQ
  params::Dict
  rp::RedPitaya
end

function DAQRedPitayaScpi()
  params = defaultDAQParams()
  println(params["ip"])
  rp = RedPitaya(params["ip"])
  daq = DAQRedPitayaScpi(params,rp)
  loadParams(daq)
  init(daq)
  return
end

function configFile(daq::DAQRedPitayaScpi)
  return Pkg.dir("MPIMeasurements","src","DAQ","Configurations","RedPitayaScpi.ini")
end

function startTx(daq::DAQRedPitayaScpi)
  dfAmplitude = mps.params["dfStrength"]
  dec = daq.params["decimation"]
  freq = daq.params["dfFreq"]

  # start sending
  send(daq.rp,"GEN:RST")
  sendAnalogSignal(daq.rp,1,"SINE",freq,
                   daq.params["calibFieldToVolt"]*dfAmplitude)
end

function stopTx(daq::DAQRedPitayaScpi)
  disableAnalogOutput(daq.rp,1)
end

function setTxParams(daq::DAQRedPitayaScpi, amplitude, phase)
    send(daq.rp,"SOUR1:VOLT $(amplitude)") # Set amplitude of output signal
end

function readData(daq::DAQRedPitayaScpi, startFrame, numPeriods)

  dec = mps.params["decimation"]

  numSampPerPeriod = numSamplesPerPeriod(daq.rp,dec,daq.params["dfFreq"])

  sleep(0.1)

  trigger = "NOW" #"AWG_NE" # or NOW

  uMeas, uRef = receiveAnalogSignalWithTrigger(daq.rp, 0, 0, numSamp, dec=dec, delay=0.01,
                typ="OLD", trigger=trigger, triggerLevel=-0.0,
                binary=true, triggerDelay=numSampPerPeriod)

  uMeas[:] = circshift(uMeas,-phaseShift(uRef, numPeriods))

  return reshape(buffer,numSampPerPeriod,numPeriods)
end
