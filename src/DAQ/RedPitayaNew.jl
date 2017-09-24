export DAQRedPitayaNew, disconnect, currentFrame, setSlowDAC, getSlowADC

import Base.write
import PyPlot.disconnect


type DAQRedPitayaNew <: AbstractDAQ
  params::Dict
  sockets::Vector{Any}
  calib
end

function DAQRedPitayaNew(params)
  daq = DAQRedPitayaNew(params,Vector{Any}(length(params["ip"])),zeros(4))
  println(params["ip"])
  init(daq)

  connectToServer(daq)
  return daq
end

DAQRedPitayaNew() = DAQRedPitayaNew(loadParams(_configFile("RedPitaya.ini")))

function currentFrame(daq::DAQRedPitayaNew)
  write_(daq.sockets[1],UInt32(1))
  v = read(daq.sockets[1],Int64)
  return v
end

export calibParams
function calibParams(daq::DAQRedPitayaNew, d)
  return reshape(daq.params["calibIntToVolt"],4,:)[:,d]
end

function dataConversionFactor(daq::DAQRedPitayaNew) #default
  return daq.calib[1:2,:]
end

immutable ParamsTypeNew
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

function Base.write(io::IO, p::ParamsTypeNew)
  n=write(io, reinterpret(Int8,[p]))
end

function write_(io::IO, p)
  n=write(io, p)
  #println("I have written $n bytes p=$p")
end

function connectToServer(daq::DAQRedPitayaNew)
  dfAmplitude = daq.params["dfStrength"]
  dec = daq.params["decimation"]
  freq = daq.params["dfFreq"]


  #  daq["acqFFValues"] = collect(linspace(0,1,10))
  #  daq["acqNumPeriods"] = length(daq["acqFFValues"])


  numSamplesPerTxPeriod = round.(Int32, daq["numSampPerPeriod"] )

  calib = zeros(Float32, 4, length(daq["ip"]))
  for d=1:length(daq["ip"])
    daq.sockets[d] = connect(daq["ip"][d],7777)
    p = ParamsType(daq["numSampPerAveragedPeriod"],
                   numSamplesPerTxPeriod[d],
                   daq["acqNumPeriods"],
                   daq["acqNumFFChannels"],
                   true,
                   daq["acqNumPeriods"] > 1,
                   daq["acqFFLinear"],
                   true,
                   daq["rpGainSetting"][1],
                   daq["rpGainSetting"][2],
                   false, false)
    write_(daq.sockets[d],p)
    println("ParamsType has $(sizeof(p)) bytes")
    if daq["acqNumPeriods"] > 1
      write_(daq.sockets[d],map(Float32,daq["acqFFValues"]))
    end
    calib[:,d] = calibParams(daq,d)
  end
  daq.calib = calib
  sleep(1e-3)
end

function startTx(daq::DAQRedPitayaNew)
  for d=1:length(daq["ip"])
    write_(daq.sockets[d],UInt32(6))
  end
end

function stopTx(daq::DAQRedPitayaNew)
  for d=1:length(daq["ip"])
    write_(daq.sockets[d],UInt32(7))
  end
end

function disconnect(daq::DAQRedPitayaNew)
  for d=1:length(daq["ip"])
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
    write_(daq.sockets[d],UInt32(3))
    write_(daq.sockets[d],Float64(amplitude[d]))
    write_(daq.sockets[d],Float64(0.0))
    write_(daq.sockets[d],Float64(phase[d]))
    write_(daq.sockets[d],Float64(0.0))
  end
end

refToField(daq::DAQRedPitayaNew) = daq.calib[3,1]*daq["calibRefToField"]

function readData(daq::DAQRedPitayaNew, numFrames, startFrame)
  dec = daq["decimation"]
  numSampPerPeriod = daq["numSampPerPeriod"]
  numSamp = numSampPerPeriod*numFrames
  numAverages = daq["acqNumAverages"]
  numAllFrames = numAverages*numFrames
  numPeriods = daq["acqNumPeriods"]

  numSampPerFrame = numSampPerPeriod * numPeriods
  numSampPerAveragedPeriod = daq["numSampPerAveragedPeriod"]
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

  uMeas = reshape(uMeas, numSampPerPeriod, numAverages, numTxChannels(daq),numPeriods,numFrames)
  uRef = reshape(uRef, numSampPerPeriod, numAverages, numTxChannels(daq),numPeriods,numFrames)

  uMeas = mean(uMeas,2)
  uRef = mean(uRef,2)

  return uMeas, uRef
end
