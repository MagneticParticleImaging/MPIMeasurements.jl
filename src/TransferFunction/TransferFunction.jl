import Base.getindex

using Interpolations

export list_tf, tf_receive_chain, plot_tf

type TransferFunction
  freq::Vector{Float64}
  data
  interp

  function TransferFunction(freq_, data)
    freq = freq_[1]:(freq_[2]-freq_[1]):freq_[end]
    interp = scale(interpolate(data,BSpline(Quadratic(Reflect())), OnCell()),freq)
    return new(freq, data, interp)
  end

  function TransferFunction(freq_, ampdata, phasedata)
    freq = freq_[1]:(freq_[2]-freq_[1]):freq_[end]
    data = ampdata.*exp(im.*phasedata)
    interp = scale(interpolate(data,BSpline(Quadratic(Reflect())), OnCell()),freq)
    return new(freq, data, interp)
  end

end

function getindex(tmf::TransferFunction, x::Real)
  a = tmf.interp[x]
  return a
end

function getindex(tmf::TransferFunction, X::Union{Vector,Range})
  return [tmf[x] for x in X]
end

function load_tf(filename::String)
  data = readcsv(filename)
  return TransferFunction(data[2:end,1],data[2:end,2],data[2:end,3])
end

function load_tf_fromMatthias(filenameAmp::String, filenamePh::String)
  data = readcsv(filenameAmp)
  ph = readcsv(filenamePh)
  freq = data[4:end,1]
  amp = 10.^(data[4:end,2]./20)
  phase = [ deg2rad(p) for p in ph[4:end,2] ]
  tf = TransferFunction(freq,amp,phase)
  #tf.data[:] ./= (freq.*2*pi*im)
  #tf.data[1] = 1
  return TransferFunction(freq, tf.data)
end

function correct_Trafo(tf::TransferFunction,trafo::TransferFunction)
  tf.data[:]./=trafo.data[:]
  tf.data[:] ./= (tf.freq.*2*pi*im)
  tf.data[1] = 1
  return TransferFunction(tf.freq, tf.data)
end

function load_tf_fromUlrich(filename::String)
  Uin = 0.0707 #V
  Rin = 50.0 #Ω
  Pin = -10.0 #DBm
  aρdata = Float64[]
  aϕdata = Float64[]
  freq = Float64[]

  file = open(filename)
  lines = readlines(file)
  for i=6:length(lines)
    tmp = split(lines[i],"\t")
    Pout = 10.0^((Pin+parse(Float64,tmp[4]))/10.0)
    f = parse(Float64,tmp[1])
    aρ = 1.0 / (Uin/sqrt(Rin*Pout)) / f
    aϕ = pi*2*parse(Float64,tmp[5])/ 180 #360
    push!(aρdata, aρ)
    push!(aϕdata, aϕ)
    push!(freq, f)
  end
  close(file)

  return TransferFunction(freq, aρdata, aϕdata)
end

function _convertTFFuncs()
  a = load_tf_fromUlrich("measurements/HH_RXCHAIN_X_20151006.S2P")
  save_tf(a,"tfdata/PreinstalledXUH.csv")

  a = load_tf_fromUlrich("measurements/HH_RXCHAIN_Y_20151006.S2P")
  save_tf(a,"tfdata/PreinstalledYUH.csv")

  a = load_tf_fromUlrich("measurements/HH_RXCHAIN_Z_20151006.S2P")
  save_tf(a,"tfdata/PreinstalledZUH.csv")


  t = load_tf_fromMatthias("measurements/MAGTRAFO50OHM.CSV", "measurements/PHASETRAFO50OHM.CSV")
  save_tf(t,"tfdata/Trafo.csv")

  t1M = load_tf_fromMatthias("measurements/MAGTRAFO1MEGOHM.CSV", "measurements/PHASETRAFO1MEGOHM.CSV")
  save_tf(t1M,"tfdata/Trafo1M.csv")

  a = load_tf_fromMatthias("measurements/XMAG.CSV", "measurements/XPH.CSV")
  b =  correct_Trafo(a,t1M)
  save_tf(b,"tfdata/PreinstalledXMG.csv")

  a = load_tf_fromMatthias("measurements/YMAG.CSV", "measurements/YPH.CSV")
  b =  correct_Trafo(a,t1M)
  save_tf(b,"tfdata/PreinstalledYMG.csv")

  a = load_tf_fromMatthias("measurements/ZMAG.CSV", "measurements/ZPH.CSV")
  b =  correct_Trafo(a,t1M)
  save_tf(b,"tfdata/PreinstalledZMG.csv")

  a = load_tf_fromMatthias("measurements/GMAG.CSV", "measurements/GGPPH.CSV")
  b =  correct_Trafo(a,t1M)
  save_tf(b,"tfdata/Gradio1.csv")

end


function save_tf(tf::TransferFunction, filename::String)
  writecsv(filename,hcat( vcat("frequency",tf.freq),
                          vcat("amplitude", abs(tf.data)),
                          vcat("phase", angle(tf.data)) ))
end

function tf_receive_chain(id::String)

  path = Pkg.dir("MPIMeasurements","src","TransferFunction","tfdata",id*".csv")

  tf = load_tf(path)
  return tf
end



function tf_receive_chain(b::BrukerFile,xx="PreinstalledXUH",
                                         yy="PreinstalledYUH",
                                         zz="PreinstalledZUH")

  ax = tf_receive_chain(xx)
  ay = tf_receive_chain(yy)
  az = tf_receive_chain(zz)

  freq = frequencies(b)
  rxchain = Complex128[]
  append!(rxchain, ax[freq])
  append!(rxchain, ay[freq])
  append!(rxchain, az[freq])
  rxchain = reshape(rxchain, length(freq),3)
  return rxchain
end


function list_tf()
  list = readdir(Pkg.dir("MPILib","src","TransferFunction","tfdata"))
  stripped_list = [ splitext(a)[1] for a in list ]
  return stripped_list
end



function plot_tf(tf::TransferFunction; fignum=312)
  freq = linspace(tf.freq[1],tf.freq[end],1000)

  figure(fignum)
  clf
  subplot(2,1,1)
  semilogy(freq./1000, abs(tf[freq]),lw=2,"r")
  subplot(2,1,2)
  plot(freq./1000, angle(tf[freq]),lw=2,"b")

end




# Example
#b = BrukerFile("/opt/mpidata/20150909_155300_LCurveStudy_1_1/1")
#rxchain = tf_receive_chain(b)
#
#semilogy(frequencies(b),squeeze(abs(rxchain[:,3])))
#

















####
# Some 1D MPI data
####

#datadir = "/opt/mpidata/20141218_165058_1DSensitivity_1_1/"
#
#bSF = BrukerFile(datadir*"57")
#bMeas = BrukerFile(datadir*"61")
#
# regular system matrix based reconstruction
#c = reconstruction(bSF, bMeas, lambd=0.1, minFreq=80e3, iterations=3, frames=1)
#
#figure(1)
#plot(c)
#
## Determine transfer function
#
#(S, SMeas, transferFunction) = simulate1DSF(bSF, D=25e-9)
#
## xspace reco

#u = getMeasurementsFT(bMeas)
#
#correctForFFPSpeed(v)
#gridDataOnSpatialIntervall(v)




#=
function tf_receive_chain(f::BrukerFile, path::AbstractString=Pkg.dir("MPILib","src","TransferFunction/"))
  pathx = path*"HH_RXCHAIN_X_20151006.S2P"
  pathy = path*"HH_RXCHAIN_Y_20151006.S2P"
  pathz = path*"HH_RXCHAIN_Z_20151006.S2P"
  rxfreq = 10000.0:931.8323952470294:1500000.0

  ax = load_tf_fromUlrich(pathx)
  ay = load_tf_fromUlrich(pathy)
  az = load_tf_fromUlrich(pathz)

  freq = frequencies(f)
  rxchain = Complex64[]
  append!(rxchain, ax[freq])
  append!(rxchain, ay[freq])
  append!(rxchain, az[freq])
  rxchain = reshape(rxchain, length(freq),3)
  return rxchain
end
=#
