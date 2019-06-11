import Base.getindex

using Interpolations, HDF5

export list_tf, tf_receive_chain, plot_tf

mutable struct TransferFunction
  freq::Vector{Float64}
  data::Matrix{ComplexF64}
  interp::Vector{Any}
  inductionFactor::Vector{Float64}

  function TransferFunction(freq_, datain::Array{T}, inductionFactor=ones(size(datain,2))) where {T<:Complex}
    freq = freq_[1]:(freq_[2]-freq_[1]):freq_[end]
    data=reshape(deepcopy(datain),size(datain,1), size(datain,2))
    interp = Any[]
    for d=1:size(datain,2)
      I = interpolate((freq_,), data[:,d], Gridded(Linear()))
      push!(interp,I)
    end
    return new(freq_, data, interp, inductionFactor)
  end

end

function TransferFunction(freq_, ampdata, phasedata, args...)
  data = ampdata.*exp.(im.*phasedata)
  return TransferFunction(freq_, data, args...)
end

function getindex(tmf::TransferFunction, x::Real, chan::Integer=1)
  a = tmf.interp[chan](x)
  return a
end


function getindex(tmf::TransferFunction, X::Union{Vector,AbstractRange},chan::Integer=1)
  return [tmf[x] for x in X]
end

function load_tf(filename::String)
  tf = h5read(filename,"/transferFunction")
  tf = copy(reshape(reinterpret(Complex{eltype(tf)}, tf), (size(tf,2),size(tf,3))))
  freq = h5read(filename,"/frequencies")
  inductionFactor = h5read(filename,"/inductionFactor")
  return TransferFunction(freq,tf,inductionFactor)
end

function combine(tf1,tf2)
  freq = tf1.freq
  data = cat(tf1.data,tf2.data, dims=2)
  inductionFactor = cat(tf1.inductionFactor, tf2.inductionFactor, dims=1)
  return TransferFunction(freq, data, inductionFactor)
end

function save_tf(tf::TransferFunction, filename::String)
  tfR = reinterpret(Float64, tf.data, (2, size(tf.data)...))
  h5write(filename, "/transferFunction", tfR)
  h5write(filename, "/frequencies", tf.freq)
  h5write(filename, "/inductionFactor", tf.inductionFactor)
  return nothing
end

function load_tf_fromMatthias(filenameAmp::String, filenamePh::String)
  data = readdlm(filenameAmp, ',')
  ph = readdlm(filenamePh, ',')
  freq = data[4:end,1]
  amp = 10 .^ (data[4:end,2] ./ 20)
  phase = [ deg2rad(p) for p in ph[4:end,2] ]
  tf = TransferFunction(freq,amp,phase)
  tf.data[:] .*= (freq .* 2*pi*im)
  tf.data[1] = 1
  return TransferFunction(freq, tf.data)
end

# The following is only required if a transformater was used to convert the
# differential signal into a regular signal
function correct_Transformator(tf::TransferFunction,trafo::TransferFunction)
  tf.data[:]./=trafo.data[:]
  #tf.data[:] ./= (tf.freq.*2*pi*im)
  #tf.data[1] = 1
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
    aρ = 1.0 / (Uin/sqrt(Rin*Pout))
    aϕ = pi*2*parse(Float64,tmp[5])/ 180 #360
    push!(aρdata, aρ)
    push!(aϕdata, aϕ)
    push!(freq, f)
  end
  close(file)

  return TransferFunction(freq, aρdata, aϕdata)
end

function load_tf_fromVNA(filename::String)
  R = 50.0 #Ω
  N=10 #5# Turns
  A=7.4894*10.0^-4 #m^2 #1.3e-3^2*pi;
  file = open(filename)
  lines = readlines(file)
  apdata = Float64[]
  aϕdata = Float64[]
  freq = Float64[]
  for i=4:length(lines)
      tmp = split(strip(lines[i])," ")
      tmp=tmp[tmp.!=""]
      f = parse(Float64,strip(tmp[1]))
      if occursin(lines[3],"# kHz S MA R 50")
          ap = parse(Float64,strip(tmp[2]))
          aphi = parse(Float64,strip(tmp[3]))
          f=f*1000
       elseif occursin(lines[3],"# Hz S DB R 50") 
            ap = 10^(parse(Float64,strip(tmp[2]))/20)
            aphi = parse(Float64,strip(tmp[3]))*pi/180
            f=f
       elseif occursin(lines[3],"# kHz S DB R 50")
            ap = 10^(parse(Float64,strip(tmp[2]))/20)
            aphi = parse(Float64,strip(tmp[3]))*pi/180
            f=f*1000
        elseif occursin(lines[3],"# MHz S DB R 50")
            ap = 10^(parse(Float64,strip(tmp[2]))/20)
            aphi = parse(Float64,strip(tmp[3]))*pi/180
            f=f*1000000
      elseif occursin(lines[3],"# kHz S RI R 50")
          tf_complex=parse(Float64,strip(tmp[2]))+im*parse(Float64,strip(tmp[3]))
          ap=abs.(tf_complex);
          aphi=angle(tf_complex)
          f=f*1000
      else
	      error("Wrong data Format! Please export in kHz domain S21 parameter with either Magnitude/Phase, DB/Phase or Real/Imaginary!")
      end
      push!(apdata, ap)
      push!(aϕdata, aphi)
      push!(freq, f)
  end
  close(file)
  #apdata .*= (freq.*2*pi)
  apdata[1] = 1
  return TransferFunction(freq, apdata, aϕdata)
end

function _convertTFFuncs()
  prefix = @__DIR__

  a = load_tf_fromUlrich(prefix*"/measurements/HH_RXCHAIN_X_20151006.S2P")
  b = load_tf_fromUlrich(prefix*"/measurements/HH_RXCHAIN_Y_20151006.S2P")
  c = load_tf_fromUlrich(prefix*"/measurements/HH_RXCHAIN_Z_20151006.S2P")
  d = combine(combine(a,b),c)
  save_tf(d,prefix*"/tfdata/PreinstalledUH.h5")

  t = load_tf_fromMatthias(prefix*"/measurements/MAGTRAFO50OHM.CSV", prefix*"/measurements/PHASETRAFO50OHM.CSV")
  t1M = load_tf_fromMatthias(prefix*"/measurements/MAGTRAFO1MEGOHM.CSV", prefix*"/measurements/PHASETRAFO1MEGOHM.CSV")

  a = load_tf_fromMatthias(prefix*"/measurements/XMAG.CSV", prefix*"/measurements/XPH.CSV")
  a =  correct_Transformator(a,t1M)
  b = load_tf_fromMatthias(prefix*"/measurements/YMAG.CSV", prefix*"/measurements/YPH.CSV")
  b =  correct_Transformator(b,t1M)
  c = load_tf_fromMatthias(prefix*"/measurements/ZMAG.CSV", prefix*"/measurements/ZPH.CSV")
  c =  correct_Transformator(c,t1M)
  e = combine(combine(a,b),c)
  save_tf(e,prefix*"/tfdata/PreinstalledMG.h5")

  d = load_tf_fromMatthias(prefix*"/measurements/GMAG.CSV", prefix*"/measurements/GGPPH.CSV")
  d =  correct_Transformator(d,t1M)
  f = combine(combine(a,d),c)
  save_tf(e,prefix*"/tfdata/Gradio1.h5")

  a = load_tf_fromVNA(prefix*"/measurements/MPS1.s1p")
  save_tf(a,prefix*"/tfdata/MPS1.h5")
end


function tf_receive_chain(id::String)

  path = joinpath(@__DIR__,"tfdata",id*".h5")

  tf = load_tf(path)
  return tf
end



function tf_receive_chain(b::BrukerFile,id="PreinstalledUH")

  tf = tf_receive_chain(id)
  freq = frequencies(b)
  rxchain = ComplexF64[]
  append!(rxchain, tf[freq,1])
  append!(rxchain, tf[freq,2])
  append!(rxchain, tf[freq,3])
  rxchain = reshape(rxchain, length(freq),3)
  return rxchain
end


function list_tf()
  list = readdir(joinpath(@__DIR__, "tfdata"))
  stripped_list = [ splitext(a)[1] for a in list ]
  return stripped_list
end



function plot_tf(tf::TransferFunction; fignum=312, filename=nothing)
  freq = linspace(tf.freq[1],tf.freq[end],1000)

  figure(fignum)
  clf
  subplot(2,1,1)
  semilogy(freq./1000, abs.(tf[freq]),lw=2,"r")
  #xlabel("frequency / kHz")
  ylabel("amplitude / a.u.")

  subplot(2,1,2)
  plot(freq./1000, angle.(tf[freq]),lw=2,"b")
  xlabel("frequency / kHz")
  ylabel("phase / rad")

  if filename != nothing
    savefig(filename)
  end
end
