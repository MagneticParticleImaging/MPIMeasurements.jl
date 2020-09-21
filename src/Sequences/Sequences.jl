export sequenceDir, sequenceList, Sequence, triangle, 
       makeTriangleSequence, makeSineSequence, makeTriSweepSequence, makeTriSweepDeadSequence

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

function triangleNegSlope(t)
  t_ = mod(t, pi)
  if 0 <= t_ < pi
    return 1.0-t_/(pi/2)
  end
end
function trianglePosSlope(t)
  t_ = mod(t, pi)
  if 0 <= t_ < pi
    return t_/(pi/2)-1
  end
end
function triangleRampUp(t)
  t_ = mod(t, pi/2)
  if 0 <= t_ < pi/2
    return t_/(pi/2)
  end
end
function triangleRampDown(t)
  t_ = mod(t, pi/2)
  if 0 <= t_ < pi/2
    return 1.0-t_/(pi/2)
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


#e.g makeTriSweepSequence("test",-5.0:1.0:5.0,4,0:1.0:4.0,1) 
function makeTriSweepSequence(name::String, XOffsetRange::StepRangeLen, periodsPerXOffset::Number, YOffsetRange::StepRangeLen, calibOffset::Bool)

  NumXOffsets = length(XOffsetRange)
  NumYOffsets = length(YOffsetRange)
  XminCurr = XOffsetRange[1]    #*calib factor
  XmaxCurr = XOffsetRange[end]  #*calib factor
  YminCurr = YOffsetRange[1]    #*calib factor
  YstepCurr = convert(Float64, YOffsetRange.step)    #*calib factor


  #toDo: conversion from current to mT for Y-channel?

  if calibOffset == true
    calibXoffsetCurr = 0.0
    calibYoffsetCurr = -0.31 #[A] offset, OPamp etc... ??
  else
    calibXoffsetCurr = 0.0
    calibYoffsetCurr = 0.0
  end


  #######################
  #crearte triangle with 2 datapoints in peak
  #which requires: slope%4 = 3
  #then every XOffset has both extrema as a datapoint
  if isodd(NumXOffsets)              
    triangleSlope = 2*NumXOffsets+1
  elseif iseven(NumXOffsets)
    triangleSlope = 2*(NumXOffsets+1)+1
  end

  if mod(triangleSlope,4) != 3
    @error "Sequence is required to have odd amount of steps. Mod(len,4) should equal 3 to obtain triangle-plateau." triangleSlope%4
  end

  flagYZero = 0
  if iseven(NumYOffsets)
    NumYOffsets +=1
    flagYZero = 1
  end
  
  #########################
  t = range(0,2*pi,length=triangleSlope)[1:end-1] 
  tri = ( ((XmaxCurr-XminCurr)/2).*triangle.(t).+(XminCurr+XmaxCurr)/2 )/maximum(triangle.(t))  #TODO: CAL offset due to plateau
   
  A = repeat(tri, ceil(Int,NumYOffsets/2) )
  B = YstepCurr .* zeros( ceil(Int,NumXOffsets/2)) .+YminCurr

  for i in 0:floor(Int,NumYOffsets)-1
    if flagYZero == 0
      B = vcat(B, YstepCurr*i .* ones(NumXOffsets) .+YminCurr)
    elseif flagYZero == 1 && i == floor(Int,NumYOffsets)-1
      B = vcat(B,zeros(NumXOffsets))   #back to zero in case of even No of Yoffsets
    else
      B = vcat(B, YstepCurr*i .* ones(NumXOffsets) .+YminCurr)
    end
  end

  B = vcat(B, zeros( floor(Int,NumXOffsets/2) )) .+ calibYoffsetCurr

  Seq = cat(A',B', dims=1)
  saveSeq(name, Sequence(Seq, periodsPerXOffset))
  return Seq
end




function makeTriSweepDeadSequence(name::String, XOffsetRange::StepRangeLen, periodsPerXOffset::Number, YOffsetRange::StepRangeLen, deadPatches::Number, calibOffset::Bool)

  NumXOffsets = length(XOffsetRange)
  NumYOffsets = length(YOffsetRange)
  XminCurr = XOffsetRange[1]    #*calib factor
  XmaxCurr = XOffsetRange[end]  #*calib factor
  YminCurr = YOffsetRange[1]    #*calib factor
  YstepCurr = convert(Float64, YOffsetRange.step)    #*calib factor


  #toDo: conversion from current to mT for Y-channel?

  if calibOffset == true
    calibXoffsetCurr = 0.0
    calibYoffsetCurr = -0.31 #[A] offset, OPamp etc... ??
  else
    calibXoffsetCurr = 0.0
    calibYoffsetCurr = 0.0
  end

  #######################
  #crearte triangle with 2 datapoints in peak
  #which requires: slope%4 = 3
  #then every XOffset has both extrema as a datapoint
  if isodd(NumXOffsets)              
    triangleSlope = 2*NumXOffsets+1
  elseif iseven(NumXOffsets)
    triangleSlope = 2*(NumXOffsets+1)+1
  end

  if mod(triangleSlope,4) != 3
    @error "Sequence is required to have odd amount of steps. Mod(len,4) should equal 3 to obtain triangle-plateau." triangleSlope%4
  end
  #########################

  t_half = range(0,pi,length=NumXOffsets)[1:end-1] 
  t_quart = range(0,pi/2,length=ceil(Int,NumXOffsets/2))[1:end-1] 

  A = triangleRampUp.(t_quart)
  B = YstepCurr .* zeros(length(A)+1) .+YminCurr 
  for i in 0:2:NumYOffsets  #if even, one offset more than necessary is created. throw away in data analysis.
    t1 = ones(deadPatches)
    t2 = triangleNegSlope.(t_half)
    B = vcat(B, YstepCurr*i .* ones(length(t1)+length(t2)) .+YminCurr)

    t3 = -ones(deadPatches)
    t4 = trianglePosSlope.(t_half)
    B = vcat(B, YstepCurr*(i+1) .* ones(length(t3)+length(t4)) .+YminCurr)

    A = vcat(A,t1,t2,t3,t4)
  end
  t5 = vcat(ones(1),triangleRampDown.(t_quart))

  A = ((XmaxCurr-XminCurr)/2).* vcat(A,t5) .+(XminCurr+XmaxCurr)/2 
  B = vcat(B, zeros(length(t5)-1)) .+ calibYoffsetCurr

  Seq = cat(A',B', dims=1)
  saveSeq(name, Sequence(Seq, periodsPerXOffset))
  return Seq
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
