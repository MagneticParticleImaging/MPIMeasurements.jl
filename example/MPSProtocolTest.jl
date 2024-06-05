dfPeriodsPerPatch = 100
dfFrequency = 25e3
baseFrequency = 125e6

numPatches = 101

divider = baseFrequency / dfFrequency

samplesPerPatch = baseFrequency / divider * dfPeriodsPerPatch

numSamples = samplesPerPatch * numPatches

channel = ContinuousElectricalChannel(id="test", dividerSteps=samplesPerPatch, divider=numSamples, amplitude=0.012u"T", phase=0u"rad", waveform=WAVEFORM_SAWTOOTH_RISING)

MPIMeasurements.values(channel)



scanner = MPIScanner("MPS")
protocol = Protocol("MPSProtocol", scanner)