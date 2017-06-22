export DAQRedPitaya

# This is a DAQ implementation using a set of RedPitayas where each RP
# is equipped with one rx and one ref channel. It uses a custom server application
# "daq_server" that is in the subdirectory "RedPitaya" and needs to be checkout
# on the RP. THe server is started using the command
#   LD_LIBRARY_PATH=/root/MPIMeasurements/src/DAQ/RedPitaya/ /root/MPIMeasurements/src/DAQ/RedPitaya/daq_server
#


type DAQRedPitaya <: AbstractDAQ
  params::Dict
  sockets::Vector{Any}
end

function DAQRedPitaya()
  params = defaultDAQParams()
  daq = DAQRedPitaya(params,Vector{Any}(length(params["ip"])))
  loadParams(daq)
  println(params["ip"])
  daq.sockets = Vector{Any}(length(params["ip"])) #ugly
  init(daq)

  return daq
end

function configFile(daq::DAQRedPitaya)
  return Pkg.dir("MPIMeasurements","src","DAQ","Configurations","RedPitaya2D.ini")
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
  for d=1:length(daq["ip"])
    daq.sockets[d] = connect(daq["ip"][d],7777)
    write(daq.sockets[d],UInt32(daq.params["numSampPerPeriod"]))
    write(daq.sockets[d],UInt32(1000000))
    write(daq.sockets[d],UInt32(1))
    write(daq.sockets[d],UInt32(1))
  end
end

function stopTx(daq::DAQRedPitaya)
  for d=1:length(daq["ip"])
    write(daq.sockets[d],UInt32(9))
    close(daq.sockets[d])
  end
end

function setTxParams(daq::DAQRedPitaya, amplitude, phase)
  for d=1:numTxChannels(daq)
    write(daq.sockets[d],UInt32(3))
    write(daq.sockets[d],Float64(amplitude[d]))
    write(daq.sockets[d],Float64(phase[d]))
  end
end


const intToVolt = 0.5/200222.109375*64 #FIXME

refToField(daq::DAQRedPitaya) = intToVolt*daq["calibRefToField"]

function readData(daq::DAQRedPitaya, numFrames, startFrame)

  dec = daq["decimation"]
  numSampPerPeriod = daq["numSampPerPeriod"]
  numSamp = numSampPerPeriod*numFrames
  numAverages = daq["acqNumAverages"]
  numAllFrames = numAverages*numFrames

  uMeas = zeros(Int16,numSampPerPeriod,numRxChannels(daq),numFrames)
  uRef = zeros(Int16,numSampPerPeriod,numTxChannels(daq),numFrames)
  wpRead = startFrame
  l=1
  chunkSize = 10000
  while l<=numFrames
    wpWrite = currentFrame(daq) # TODO handle wpWrite overflow
    while wpRead >= wpWrite
      wpWrite = currentFrame(daq)
    end
    chunk = min(wpWrite-wpRead,chunkSize)
    if l+chunk > numFrames
      chunk = numFrames - l+1
    end

    println("Read from $wpRead until $(wpRead+chunk-1), WpWrite $(wpWrite)")

    for d=1:numRxChannels(daq)
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(1))
      uMeas[:,d,l:(l+chunk-1)] = read(daq.sockets[d],Int16,chunk * numSampPerPeriod)
    end
    for d=1:numTxChannels(daq)
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(2))
      uRef[:,d,l:(l+chunk-1)] = read(daq.sockets[d],Int16,chunk * numSampPerPeriod)
    end
    l += chunk
    wpRead += chunk
  end

  return uMeas, uRef
end
