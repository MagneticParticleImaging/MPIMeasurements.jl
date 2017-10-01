export DAQRedPitayaNew, disconnect, currentFrame, setSlowDAC, getSlowADC, connectToServer,
       reinit

import Base.write
import PyPlot.disconnect



type DAQRedPitayaNew <: AbstractDAQ
  params::DAQParams
  sockets::Vector{TCPSocket}
  ip::Vector{String}
end


function DAQRedPitayaNew(params)
  p = DAQParams(params)
  D = length(params["ip"])

  daq = DAQRedPitayaNew(p, Vector{TCPSocket}(D), params["ip"])

  println(daq.ip)

  connectToServer(daq)

  finalizer(daq, d -> disconnect(d))
  return daq
end

function reinit(daq::DAQRedPitayaNew)
  disconnect(daq)
  sleep(0.3)
  connectToServer(daq)
  return nothing
end

function updateParams!(daq::DAQRedPitayaNew, params_::Dict)
  disconnect(daq)
  sleep(0.1)
  daq.params = DAQParams(params_)
  connectToServer(daq)
end

numRxChannels(daq::DAQRedPitayaNew) = length(daq.ip)

function currentFrame(daq::DAQRedPitayaNew)
  cf = zeros(Int64, length(daq.ip))
  for d=1:length(daq.ip)
    write_(daq.sockets[d],UInt32(1))
    cf[d] = read(daq.sockets[d],Int64)
  end
  println("Current frame: $cf")
  return minimum(cf)
end

export calibParams
function calibParams(daq::DAQRedPitayaNew, d)
  return daq.params.calibIntToVolt[:,d]
  #return reshape(daq.params["calibIntToVolt"],4,:)[:,d]
end

function dataConversionFactor(daq::DAQRedPitayaNew)
  return daq.params.calibIntToVolt[1:2,:]
end

immutable ParamsTypeNew
  decimation::Int32
  numSamplesPerPeriod::Int32
  numPeriodsPerFrame::Int32
  numPatches::Int32
  numFFChannels::Int32
  modulus1::Int32
  modulus2::Int32
  modulus3::Int32
  modulus4::Int32
  txEnabled::Bool
  ffEnabled::Bool
  ffLinear::Bool
  isMaster::Bool
  isHighGainChA::Bool
  isHighGainChB::Bool
  pad1::Bool
  pad2::Bool
end

function Base.write(io::IO, p::ParamsTypeNew)
  n=write(io, reinterpret(Int8,[p]))
end

function write_(io::IO, p)
  n=write(io, p)
  #println("I have written $n bytes p=$p")
end

function connectToServer(daq::DAQRedPitayaNew)
  dfAmplitude = daq.params.dfStrength
  dec = daq.params.decimation
  freq = daq.params.dfFreq

  numSampPerAveragedPeriod = daq.params.numSampPerPeriod * daq.params.acqNumAverages

  modulus = ones(Int32,4)
  modulus[1:length(daq.params.dfDivider)] = daq.params.dfDivider

  for d=1:length(daq.ip)
    daq.sockets[d] = connect(daq.ip[d],7777)
    p = ParamsTypeNew(daq.params.decimation,
                   numSampPerAveragedPeriod,
                   daq.params.acqNumPeriods,
                   div(length(daq.params.acqFFValues),daq.params.acqNumFFChannels),
                   daq.params.acqNumFFChannels,
                   modulus[1],
                   modulus[2],
                   modulus[3],
                   modulus[4],
                   true,
                   daq.params.acqNumPeriods > 1,
                   daq.params.acqFFLinear,
                   d == 1,
                   true,
                   true,
                   false, false)
    write_(daq.sockets[d],p)
    println("ParamsType has $(sizeof(p)) bytes")
    if daq.params.acqNumPeriods > 1
      write_(daq.sockets[d],map(Float32,daq.params.acqFFValues))
    end
  end
  sleep(1e-6)
end

function startTx(daq::DAQRedPitayaNew)
  for d=1:length(daq.ip)
    write_(daq.sockets[d],UInt32(6))
  end
  return nothing
end

function stopTx(daq::DAQRedPitayaNew)
  for d=1:length(daq.ip)
    write_(daq.sockets[d],UInt32(7))
  end
end

function disconnect(daq::DAQRedPitayaNew)
  for d=1:length(daq.ip)
    write_(daq.sockets[d],UInt32(9))
    close(daq.sockets[d])
  end
end

function setSlowDAC(daq::DAQRedPitayaNew, value, channel, d=1)
  write_(daq.sockets[d],UInt32(4))
  write_(daq.sockets[d],UInt64(channel))
  write_(daq.sockets[d],Float32(value))
  return nothing
end

function getSlowADC(daq::DAQRedPitayaNew, channel, d=1)
  write_(daq.sockets[d],UInt32(5))
  write_(daq.sockets[d],UInt64(channel))
  return read(daq.sockets[d],Float32)
end

function setTxParams(daq::DAQRedPitayaNew, amplitude, phase)
  for d=1:numTxChannels(daq)
    tmp = zeros(Float32,4)
    write_(daq.sockets[d],UInt32(3))
    # amplitudes channel A
    tmp[d] = amplitude[d]
    write_(daq.sockets[d],tmp)
    # amplitudes channel B
    write_(daq.sockets[d],zeros(Float32,4))
    # phases channel A
    tmp[d] = phase[d]
    write_(daq.sockets[d],tmp)
    # phases channel B
    write_(daq.sockets[d],zeros(Float32,4))
  end
end

#TODO: calibRefToField should be multidimensional
refToField(daq::DAQRedPitayaNew, d::Int64) = daq.params.calibRefToField[d]

function readData(daq::DAQRedPitayaNew, numFrames, startFrame)
  dec = daq.params.decimation
  numSampPerPeriod = daq.params.numSampPerPeriod
  numSamp = numSampPerPeriod*numFrames
  numAverages = daq.params.acqNumAverages
  numAllFrames = numAverages*numFrames
  numPeriods = daq.params.acqNumPeriods

  numSampPerFrame = numSampPerPeriod * numPeriods
  numSampPerAveragedPeriod =  numSampPerPeriod * numAverages
  numSampPerAveragedFrame = numSampPerAveragedPeriod * numPeriods

  uMeas = zeros(Int32,numSampPerAveragedPeriod,numRxChannels(daq),numPeriods,numFrames)
  uRef = zeros(Int32,numSampPerAveragedPeriod,numTxChannels(daq),numPeriods,numFrames)
  wpRead = startFrame
  l=1

  chunkSize = max(1,  round(Int,1000000 / numSampPerAveragedFrame)  )
  println("chunkSize = $chunkSize")
  while l<=numFrames
    wpWrite = currentFrame(daq) # TODO handle wpWrite overflow
    while wpRead >= wpWrite
      wpWrite = currentFrame(daq)
      println(wpWrite)
    end
    chunk = min(wpWrite-wpRead,chunkSize)
    println(chunk)
    if l+chunk > numFrames
      chunk = numFrames - l+1
    end

    println("Read from $wpRead until $(wpRead+chunk-1), WpWrite $(wpWrite), chunk=$(chunk)")

    #TODO decouple Tx from Rx Channels

    for d=1:numRxChannels(daq)
      write(daq.sockets[d],UInt32(2))
      write(daq.sockets[d],UInt64(wpRead))
      write(daq.sockets[d],UInt64(chunk))
      write(daq.sockets[d],UInt64(1))
      u = read(daq.sockets[d],Int16, 2*chunk * numSampPerAveragedFrame)
      uMeas[:,d,:,l:(l+chunk-1)] = u[1:2:end]
      uRef[:,d,:,l:(l+chunk-1)] = u[2:2:end]
    end

    l += chunk
    wpRead += chunk
  end

  uMeas = reshape(uMeas, numSampPerPeriod, numAverages, numRxChannels(daq),numPeriods,numFrames)
  uRef = reshape(uRef, numSampPerPeriod, numAverages, numTxChannels(daq),numPeriods,numFrames)

  uMeas = mean(uMeas,2)
  uRef = mean(uRef,2)

  uMeas = reshape(uMeas,numSampPerPeriod, numTxChannels(daq),numPeriods,numFrames)
  uRef = reshape(uRef, numSampPerPeriod, numTxChannels(daq),numPeriods,numFrames)

  return uMeas, uRef
end
