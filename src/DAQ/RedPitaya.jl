export DAQRedPitaya

# This is a DAQ implementation using a set of RedPitayas where each RP
# is equipped with one rx and one ref channel. It uses a custom server application
# "daq_server" that is in the subdirectory "RedPitaya" and needs to be checkout
# on the RP. THe server is started using the command
#   LD_LIBRARY_PATH=/root/MPIMeasurements/src/DAQ/RedPitaya/ /root/MPIMeasurements/src/DAQ/RedPitaya/daq_server
#

import Base.write

type DAQRedPitaya <: AbstractDAQ
  params::Dict
  sockets::Vector{Any}
  calib
end

function DAQRedPitaya(params)
  daq = DAQRedPitaya(params,Vector{Any}(length(params["ip"])),zeros(4))
  println(params["ip"])
  init(daq)

  return daq
end

DAQRedPitaya() = DAQRedPitaya(loadParams(_configFile("RedPitaya.ini")))

function currentFrame(daq::DAQRedPitaya)
  write_(daq.sockets[1],UInt32(1))
  v = read(daq.sockets[1],Int64)
  return v
end

export calibParams
function calibParams(daq::DAQRedPitaya, d)
  write_(daq.sockets[d],UInt32(4))
  calib = read(daq.sockets[d],Float32,4)
  return calib
end

function dataConversionFactor(daq::DAQRedPitaya) #default
  return daq.calib[1:2,:]
end

immutable ParamsType
  numSamplesPerPeriod::Int32
  numSamplesPerTxPeriod::Int32
  numPeriodsPerFrame::Int32
  numFFChannels::Int32
  txEnabled::Bool
  ffEnabled::Bool
  ffLinear::Bool
  isMaster::Bool
  isHighGainChA::Bool
  isHighGainChB::Bool
  pad1::Bool
  pad2::Bool
end

function Base.write(io::IO, p::ParamsType)
  n=write(io, reinterpret(Int8,[p]))
end

function write_(io::IO, p)
  n=write(io, p)
  println("I have written $n bytes p=$p")
end

function startTx(daq::DAQRedPitaya)
  dfAmplitude = daq.params["dfStrength"]
  dec = daq.params["decimation"]
  freq = daq.params["dfFreq"]

  numSamplesPerTxPeriod = round(Int32, daq["numSampPerPeriod"] ./
                                       (daq["dfPeriod"] .* daq["dfFreq"]))

  calib = zeros(Float32, 4, length(daq["ip"]))
  for d=1:length(daq["ip"])
    daq.sockets[d] = connect(daq["ip"][d],7777)
    p = ParamsType(daq["numSampPerPeriod"],
                   numSamplesPerTxPeriod[d],
                   daq["acqNumPatches"],
                   daq["acqNumFFChannels"],
                   true,
                   daq["acqNumPatches"] > 1,
                   daq["acqFFLinear"],
                   true,
                   daq["rpGainSetting"][1],
                   daq["rpGainSetting"][2],
                   false, false)
    write_(daq.sockets[d],p)
    println("ParamsType has $(sizeof(p)) bytes")
    if daq["acqNumPatches"] > 1
      write_(daq.sockets[d],map(Float32,daq["acqFFValues"]))
    end
    calib[:,d] = calibParams(daq,d)
  end
  daq.calib = calib
end

function stopTx(daq::DAQRedPitaya)
  for d=1:length(daq["ip"])
    write_(daq.sockets[d],UInt32(9))
    close(daq.sockets[d])
  end
end

function setTxParams(daq::DAQRedPitaya, amplitude, phase)
  for d=1:numTxChannels(daq)
    write_(daq.sockets[d],UInt32(3))
    write_(daq.sockets[d],Float64(amplitude[d]))
    write_(daq.sockets[d],Float64(phase[d]))
  end
end

refToField(daq::DAQRedPitaya) = daq.calib[3,1]*daq["calibRefToField"]

function readData(daq::DAQRedPitaya, numFrames, startFrame)

  dec = daq["decimation"]
  numSampPerPeriod = daq["numSampPerPeriod"]
  numSamp = numSampPerPeriod*numFrames
  numAverages = daq["acqNumAverages"]
  numAllFrames = numAverages*numFrames
  numPatches = daq["acqNumPatches"]

  numSampPerFrame = numSampPerPeriod * numPatches

  uMeas = zeros(Int16,numSampPerPeriod,numRxChannels(daq),numPatches,numFrames)
  uRef = zeros(Int16,numSampPerPeriod,numTxChannels(daq),numPatches,numFrames)
  wpRead = startFrame
  l=1
  chunkSize = 1000
  while l<=numFrames
    wpWrite = currentFrame(daq) # TODO handle wpWrite overflow
    while wpRead >= wpWrite
      wpWrite = currentFrame(daq)
    end
    chunk = min(wpWrite-wpRead,chunkSize)
    println(chunk)
    if l+chunk > numFrames
      chunk = numFrames - l+1
    end

    println("Read from $wpRead until $(wpRead+chunk-1), WpWrite $(wpWrite), chunk=$(chunk)")

    for d=1:numRxChannels(daq)
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(1))
      uMeas[:,d,:,l:(l+chunk-1)] = read(daq.sockets[d],Int16,chunk * numSampPerFrame)
    end
    for d=1:numTxChannels(daq)
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(2))
      uRef[:,d,:,l:(l+chunk-1)] = read(daq.sockets[d],Int16,chunk * numSampPerFrame)
    end

    l += chunk
    wpRead += chunk
  end

  return uMeas, uRef
end
