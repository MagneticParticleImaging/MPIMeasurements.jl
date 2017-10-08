import Redpitaya: measureTransferFunction


#=
Measure the transfer function of all receive chains

We use the last frequency of the send channels
=#
function measureTransferFunction(daq::DAQRedPitayaNew)

  modulus = 4800 # TODO adapt me
  daq.params.decimation
  daq.params.dfBaseFrequency
  numFreq = div(modulus,daq.params.decimation*2*2)

  tf = zeros(Complex128, numFreq, numTxChannels(daq))
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
      tf[k,d] = rfft(u,1)[numPeriods+1,d,1,1] / rfft(uref,1)[numPeriods+1,d,1,1]
    end
  end

  stopTx(daq)
  #disconnect(daq)

  return freqs, tf
end
