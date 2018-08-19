#import Redpitaya: measureTransferFunction


#=
Measure the transfer function of all receive chains

We use the last frequency of the send channels
=#
function measureTransferFunction(daq::DAQRedPitayaScpiNew)

  modulus = 4800 # TODO adapt me
  numFreq = div(modulus,daq.params.decimation*2)-1

  tf = zeros(ComplexF64, numFreq, numTxChannels(daq), 3)
  uall = zeros(ComplexF64, numFreq, numFreq+2, numTxChannels(daq), 2)
  ualltime = zeros(Float64, numFreq, (numFreq+1)*2, numTxChannels(daq), 2)
  freqs = [ daq.params.dfBaseFrequency/modulus*k for k=1:numFreq ]

  startTx(daq)

  for (k,freq) in enumerate(freqs)

    println("Frequency = $(freq) Hz")

    # start sending
    for d=1:numTxChannels(daq)
      setTxParamsAll(daq,d,Float32[0.0,0.0,0.0,0.5],
                         Float32[0.0,0.0,0.0,0.0],
                         UInt32[1,1,1,k])
    end

    sleep(0.1)
    # receive data
    u, uref = readData(daq,1,currentFrame(daq))

    numPeriods = k
    for d=1:numTxChannels(daq)
      ualltime[k,:,d,1] = u
      ualltime[k,:,d,2] = uref
      uall[k,:,d,1] = rfft(u,1)
      uall[k,:,d,2] = rfft(uref,1)
      tf[k,d,1] = uall[k,numPeriods+1,d,1]
      tf[k,d,2] = uall[k,numPeriods+1,d,2]
      tf[k,d,3] = tf[k,d,1] / tf[k,d,2]
    end
  end

  stopTx(daq)
  #disconnect(daq)

  return freqs, tf, uall, ualltime
end
