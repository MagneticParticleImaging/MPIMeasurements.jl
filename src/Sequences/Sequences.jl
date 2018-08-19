export makeSequence, sequenceDir

#6.312341575312002
#13.705627903244254

sequenceDir() = @__DIR__


function makeSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)
  A=collect(linspace(minCurr,maxCurr,patches))

  C = cat(A',reverse(A',dims=2), dims=1)
  B=repeat(cat(C,reverse(C,dims=2), dims=2), inner=(1,periodsPerPatch))
  B = circshift(B,(0,div(size(B,2),4)))
  writedlm(joinpath(@__DIR__, name*".csv"), B, ',')
  return B
end

function makeSineSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)

  t=linspace(0,2*pi,patches+1)[1:end-1]
  A=((maxCurr-minCurr)/2).*sin.(t).+(minCurr+maxCurr)/2
  B=-(((maxCurr-minCurr)/2).*sin.(t)).+(minCurr+maxCurr)/2

  C = cat(A',B', dims=1)
  D=repeat(C, inner=(1,periodsPerPatch))

  writedlm(joinpath(@__DIR__, name*".csv"), D, ',')
  return D
end
