export sequenceDir, sequenceList, Sequence, triangle, 
       makeTriangleSequence, makeSineSequence

#6.312341575312002
#13.705627903244254

sequenceDir() = @__DIR__


sequenceList() = String[ splitext(seq)[1] for seq in filter(a->contains(a,".toml"),readdir(sequenceDir()))] 

mutable struct Sequence
  values::Matrix{Float64}
  numPeriodsPerPatch::Int64
end

MPIFiles.acqNumPeriodsPerFrame(s::Sequence) = size(s.values,2)*s.numPeriodsPerPatch
MPIFiles.acqNumPatches(s::Sequence) = size(s.values,2)
MPIFiles.acqNumPeriodsPerPatch(s::Sequence) = s.numPeriodsPerPatch

function Sequence(name::String)
  filename = joinpath(sequenceDir(),name*".toml")
  p = TOML.parsefile(filename)
  values = reshape(p["values"], :, p["numPatches"])
  return Sequence(values, p["numPeriodsPerPatch"])
end

function saveSeq(name::String, seq::Sequence)
  p = Dict{String,Any}()
  p["numPeriodsPerPatch"] = seq.numPeriodsPerPatch
  p["values"] = seq.values
  p["numPatches"] = size(seq.values, 2)

  filename = joinpath(sequenceDir(),name*".toml")
  open(filename, "w") do f
    TOML.print(f, p)
  end
end


function makeSineSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)

  t = range(0,2*pi,length=patches+1)[1:end-1]

  A = ((maxCurr-minCurr)/2).*sin.(t).+(minCurr+maxCurr)/2
  B = -(((maxCurr-minCurr)/2).*sin.(t)).+(minCurr+maxCurr)/2

  C = cat(A',B', dims=1)

  saveSeq(name, Sequence(C, periodsPerPatch))
  return C
end

function triangle(t)
  t_ = mod(t, 2*pi)
  if 0 <= t_ < pi/2
    return t_/(pi/2)
  elseif pi/2 <= t_ < 3*pi/2
    return 2.0-t_/(pi/2)
  elseif 3*pi/2 <= t_ < 2*pi
    return t_/(pi/2) - 4.0 
  end
end

function makeTriangleSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)

  t = range(0,2*pi,length=patches+1)[1:end-1]

  A = ((maxCurr-minCurr)/2).*triangle.(t).+(minCurr+maxCurr)/2
  B = -(((maxCurr-minCurr)/2).*triangle.(t)).+(minCurr+maxCurr)/2

  C = cat(A',B', dims=1)

  saveSeq(name, Sequence(C, periodsPerPatch))
  return C
end


#=
function makeSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)
  A=collect(linspace(minCurr,maxCurr,patches))

  C = cat(A',reverse(A',dims=2), dims=1)
  B=repeat(cat(C,reverse(C,dims=2), dims=2), inner=(1,periodsPerPatch))
  B = circshift(B,(0,div(size(B,2),4)))
  writedlm(joinpath(@__DIR__, name*".csv"), B, ',')
  return B
end


function makeSineSequence(name::String, minCurrCh1, maxCurrCh1,minCurrCh2, maxCurrCh2, patches, periodsPerPatch)

  t=range(0,2*pi,length=patches+1)[1:end-1]

  A=((maxCurrCh1-minCurrCh1)/2).*sin.(t).+(minCurrCh1+maxCurrCh1)/2
  B=-(((maxCurrCh2-minCurrCh2)/2).*sin.(t)).+(minCurrCh2+maxCurrCh2)/2

  C = cat(A',B', dims=1)
  D=repeat(C, inner=(1,periodsPerPatch))

  writedlm(joinpath(@__DIR__, name*".csv"), D, ',')
  return D
end
function makeSineSequenceTest(name::String, minCurr, maxCurr, patches, periodsPerPatch)

  t=range(0,2*pi,length=patches+1)[1:end-1]
  A=circshift(((maxCurr-minCurr)/2).*sin.(t).+(minCurr+maxCurr)/2,-6)
  B=circshift(-(((maxCurr-minCurr)/2).*sin.(t)).+(minCurr+maxCurr)/2,-6)

  C = cat(A',B', dims=1)
  D=repeat(C, inner=(1,periodsPerPatch))

  writedlm(joinpath(@__DIR__, name*".csv"), D, ',')
  return D
end

=#
