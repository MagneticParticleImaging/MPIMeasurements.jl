using Redpitaya

export MPS

type MPS
  rp
  params::Dict
end

# DO NOT USE
type Spectrometer
  ip::String
  params::Dict
  socket
  numSamplesPerPeriod # put me into the params dict
end

include("Parameters.jl")

function MPS(ip::String)

  params = defaultMPSParams()
  rp = RedPitaya(ip)
  mps = MPS(rp, params)
  loadParams(mps)

  return mps
end

MPS() = MPS("10.167.6.87")

function Spectrometer(ip::String, numSamplesPerPeriod=78)

  params = defaultMPSParams()

  mps = MPS(ip, params, nothing, numSamplesPerPeriod)

  loadParams(mps)

  return mps
end


include("Measurements.jl")
include("UI.jl")

function prepareForVisu{T}(u::Matrix{T}, numPeriods)
  numAverages = div(size(u,2),numPeriods)
  uNew = reshape(u,size(u,1)*numPeriods, numAverages)
  uOut = mean(uNew,2)
  return uOut
end

export showMPSData
function showMPSData(u)  
  u_ = prepareForVisu(u,10)
  figure(1)
  clf()
  subplot(2,1,1)
  plot(u_)
  subplot(2,1,2)
  semilogy(abs(rfft(u_)),"o-b",lw=2)
  sleep(0.1)
end

function showMPSData(mps,u)
  u_ = prepareForVisu(u,10)
  figure(1)
  clf()
  subplot(2,1,1)
  plot(u_)
  subplot(2,1,2)
  uhat = abs(rfft(u_))
  freq = (0:(length(uhat)-1)) * mps.params[:dfBaseFrequency] / mps.params[:dfDivider][1,1,1]  /10

  semilogy(freq,uhat,"o-b",lw=2)
  sleep(0.1)
end




export loadMPSData
function loadMPSData(filename)
  f = MPIFiles.MPIFile(filename)
  u = MPIFiles.measData(f)[:,:,1,1] 
  uBG = MPIFiles.measBGData(f)[:,:,1,1]
  uBGMean = mean(uBG[:,:,1,1],2)

  return u .- uBGMean
end





# DO NOT USE
export measurementCont
function measurementCont(mps::Spectrometer)
  startTx(mps)

  wpRead = waitForControlLoop(mps)

  try
      while true
        uMeas = readData(mps,getCurrentWP(mps),1000)
        showMPSData(uMeas)
        sleep(0.01)
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(mps)
      else
        rethrow(x)
      end
  end

end
