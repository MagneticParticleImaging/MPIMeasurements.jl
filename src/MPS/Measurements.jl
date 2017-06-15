export measurement

# low level

function startTx(mps::Spectrometer)
  mps.socket = connect(mps.ip,7777)
  write(mps.socket,UInt32(mps.numSamplesPerPeriod))
  write(mps.socket,UInt32(1000000))
  write(mps.socket,UInt32(1))
  write(mps.socket,UInt32(1))
end

function getCurrentWP(mps::Spectrometer)
  write(mps.socket,UInt32(1))
  return read(mps.socket,Int64)
end

function waitForControlLoop(mps::Spectrometer)
  while true
    write(mps.socket,UInt32(0))
    if read(mps.socket,Int32) == 0
      break
    end
  end

  return getCurrentWP(mps)
end

function stopTx(mps::Spectrometer)
  write(mps.socket,UInt32(3))
  close(mps.socket)
end

function measurement(mps::Spectrometer; numPeriods=1000)

    startTx(mps)

    wpRead = waitForControlLoop(mps)

    uMeas = readData(mps,wpRead,numPeriods)

    stopTx(mps)

    return uMeas
end

function readData(mps::Spectrometer, startFrame, numPeriods)

    uMeas = zeros(Int16,mps.numSamplesPerPeriod,numPeriods)
    wpRead = startFrame
    l=1
    chunkSize = 10000
    while l<numPeriods
      wpWrite = getCurrentWP(mps)

      chunk = min(wpWrite-wpRead,chunkSize)
      if l+chunk > numPeriods
        chunk = numPeriods - l+1
      end

      println("Read from $wpRead until $(wpRead+chunk-1), WpWrite $(wpWrite)")

      write(mps.socket,UInt32(2))
      write(mps.socket,UInt64(wpRead))
      write(mps.socket,UInt64(chunk))
      uMeas[:,l:(l+chunk-1)] = read(mps.socket,Int16,chunk * mps.numSamplesPerPeriod)
      l+=chunk
      wpRead += chunk
    end

    return uMeas
end

# low level OLD: uses SCPI interface
function measurement(mps::MPS,params=Dict{String,Any}())
  updateParams(mps, params)

  nAverages = mps.params["rxNumAverages"]
  amplitude = mps.params["dfStrength"]

  dec = mps.params["decimation"]
  freq = div(mps.params["dfBaseFrequency"],mps.params["dfDivider"])

  numPeriods = mps.params["measNumFrames"]
  freqR = roundFreq(mps.rp,dec,freq)
  numSampPerPeriod = numSamplesPerPeriod(mps.rp,dec,freqR)
  numSamp = numSampPerPeriod*numPeriods

  println("Frequency = $freqR Hz")
  println("Number Sampling Points per Period: $numSampPerPeriod")

  println("Amplitude = $(amplitude*1000) mT")
  # start sending
  send(mps.rp,"GEN:RST")
  sendAnalogSignal(mps.rp,1,"SINE",freqR,
                   mps.params["calibFieldToVolt"]*amplitude)
  sleep(0.3)
  buffer = zeros(Float32,numSamp)
  for n=1:nAverages
    trigger = "NOW" #"AWG_NE" # or NOW

    uMeas, uRef = receiveAnalogSignalWithTrigger(mps.rp, 0, 0, numSamp, dec=dec, delay=0.01,
                typ="OLD", trigger=trigger, triggerLevel=-0.0,
                binary=true, triggerDelay=numSampPerPeriod)

    uMeas[:] = circshift(uMeas,-phaseShift(uRef, numPeriods))

    #if (maximum(uRef)*mps.params[:calibRefToField] - amplitude)/amplitude > 0.01
    #  println("Field not reached!")
    #end

    buffer[:] .+= uMeas
  end
  buffer[:] ./= nAverages

  disableAnalogOutput(mps.rp,1)

  return reshape(buffer,numSampPerPeriod,numPeriods)
end

# high level: This stores as MDF
function measurement(mps::MPS, filename::String, params_=Dict{String,Any}())
  updateParams(mps, params_)

  params = copy(mps.params)

  dec = mps.params["decimation"]
  freq = div(mps.params["dfBaseFrequency"],mps.params["dfDivider"])
  freqR = roundFreq(mps.rp,dec,freq)
  numSampPerPeriod = numSamplesPerPeriod(mps.rp,dec,freqR)


  params["studyIsSimulation"] = false
  params["studyIsCalibration"] = false

  # acquisition parameters
  params["acqFramePeriod"] = 1/freqR
  params["acqNumPatches"] = 1
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2)
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2)

  # drivefield parameters
  params["dfStrength"] = reshape([mps.params["dfStrength"]],1,1,1)
  params["dfPhase"] = reshape([mps.params["dfPhase"]],1,1,1)
  params["dfBaseFrequency"] = mps.params["dfBaseFrequency"]
  params["dfDivider"] = reshape([mps.params["dfDivider"]],1,1)
  params["dfPeriod"] = params["acqFramePeriod"]
  params["dfWaveform"] = "sine"

  # receiver parameters
  params["rxNumChannels"] = 1
  params["rxBandwidth"] = mps.params["dfBaseFrequency"] / dec / 2
  params["rxNumSamplingPoints"] = [numSampPerPeriod]
  #params["rxFrequencies"] = rxFrequencies(f)
  #params["rxTransferFunction"] = rxTransferFunction(f)

  # measurement
  params["measUnit"] = "V"
  params["measDataConversionFactor"] = [1.0, 0]
  params["measNumFrames"] = mps.params["measNumFrames"] * 2
  params["measIsAveraged"] = false
  params["measIsTransposed"] = false
  params["measIsFrameSelection"] = false
  params["measIsBGCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFramePermutation"] = false
  params["measIsFrequencySelection"] = false
  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["measIsBGFrame"] = cat(1, ones(Bool,mps.params["measNumFrames"]),
                                   zeros(Bool,mps.params["measNumFrames"]))


  println("Remove the sample to perform BG measurement and press enter")
  readline(STDIN)
  uBG = measurement(mps)

  println("Put in the sample to perform measurement and press enter")
  readline(STDIN)
  uFG = measurement(mps)
  params["measData"] = cat(4,reshape(uBG,size(uBG,1),1,1,size(uBG,2)),
                             reshape(uFG,size(uFG,1),1,1,size(uFG,2)))

  MPIFiles.saveasMDF( filename, params )
  return filename
end

function measurement(mps::MPS, mdf::MDFDatasetStore, params=Dict{String,Any})
  updateParams(mps, params)

  name = params["studyName"]
  path = joinpath( studydir(mdf), name)
  subject = ""
  date = ""

  newStudy = Study(path,name,subject,date)

  addStudy(mdf, newStudy)
  expNum = getNewExperimentNum(mdf, newStudy)

  mps.params["studyName"] = params["studyName"]
  mps.params["studyExperiment"] = expNum


  filename = joinpath(studydir(mdf),newStudy.name,string(expNum)*".mdf")
  measurement(mps, filename )
  return filename
end
