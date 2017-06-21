export DAQRedPitaya

type DAQRedPitaya <: AbstractDAQ
  params::Dict
  ip::Vector{String}
  sockets::Vector{Any}
end

function DAQRedPitaya()
  params = defaultDAQParams()
  println(params["ip"])
  daq = DAQRedPitaya(params,params["ip"],Vector{Any}(length(params["ip"])))
  loadParams(daq)
  init(daq)

  return daq
end

function configFile(daq::DAQRedPitaya)
  return Pkg.dir("MPIMeasurements","src","DAQ","Configurations","RedPitaya.ini")
end

function controlPhaseDone(daq::DAQRedPitaya)
  #write(daq.socket,UInt32(0))
  #return read(daq.socket,Int32) == 0
  return true
end

function currentFrame(daq::DAQRedPitaya)
  write(daq.sockets[1],UInt32(1))
  return read(daq.sockets[1],Int64)
end

function startTx(daq::DAQRedPitaya)
  dfAmplitude = daq.params["dfStrength"]
  dec = daq.params["decimation"]
  freq = daq.params["dfFreq"]

  #daq.params["calibFieldToVolt"]*dfAmplitude
  for d=1:length(daq.ip)
    daq.sockets[d] = connect(daq.ip[d],7777)
    write(daq.sockets[d],UInt32(daq.params["numSampPerPeriod"]))
    write(daq.sockets[d],UInt32(1000000))
    write(daq.sockets[d],UInt32(1))
    write(daq.sockets[d],UInt32(1))
  end
end

function stopTx(daq::DAQRedPitaya)
  for d=1:length(daq.ip)
    write(daq.sockets[d],UInt32(9))
    close(daq.sockets[d])
  end
end

function setTxParams(daq::DAQRedPitaya, amplitude, phase)
  for d=1:length(daq.ip)
    write(daq.sockets[d],UInt32(3))
    write(daq.sockets[d],Float64(amplitude[d]))
    write(daq.sockets[d],Float64(phase[d]))
  end
end


const intToVolt = 0.5/200222.109375*64

refToField(daq::DAQRedPitaya) = intToVolt*daq["calibRefToField"][1]

function readData(daq::DAQRedPitaya, numFrames, startFrame)

  dec = daq["decimation"]
  numSampPerPeriod = daq["numSampPerPeriod"]
  numSamp = numSampPerPeriod*numFrames
  numChannels = length(daq["dfDivider"])
  numAverages = daq["acqNumAverages"]
  numAllFrames = numAverages*numFrames

  uMeas = zeros(Int16,numSampPerPeriod,numChannels,numFrames)
  uRef = zeros(Int16,numSampPerPeriod,numChannels,numFrames)
  wpRead = startFrame
  l=1
  chunkSize = 10000
  while l<=numFrames
    wpWrite = currentFrame(daq) # TODO handle wpWrite overflow

    chunk = min(wpWrite-wpRead,chunkSize)
    if l+chunk > numFrames
      chunk = numFrames - l+1
    end

    println("Read from $wpRead until $(wpRead+chunk-1), WpWrite $(wpWrite)")

    for d=1:numChannels
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(1))
      uMeas[:,d,l:(l+chunk-1)] = read(daq.sockets[d],Int16,chunk * numSampPerPeriod)
    end
    for d=1:numChannels
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(1))
      uRef[:,d,l:(l+chunk-1)] = read(daq.sockets[d],Int16,chunk * numSampPerPeriod)
    end
    l += chunk
    wpRead += chunk
  end

  return uMeas, uRef
end
