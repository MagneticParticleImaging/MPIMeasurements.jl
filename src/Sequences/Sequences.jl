export makeSequence

#6.312341575312002
#13.705627903244254


function makeSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)
  A=collect(linspace(minCurr,maxCurr,patches))

  C = cat(1,A',flipdim(A',2))
  B=repeat(cat(2,C,flipdim(C,2)), inner=(1,periodsPerPatch))
  B = circshift(B,(0,div(size(B,2),4)))
  writecsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                  name*".csv"), B)
  return B
end

function makeSineSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)

  t=linspace(0,2*pi,patches+1)[1:end-1]
  A=((maxCurr-minCurr)/2).*sin.(t).+(minCurr+maxCurr)/2
  B=-(((maxCurr-minCurr)/2).*sin.(t)).+(minCurr+maxCurr)/2

  C = cat(1,A',B')
  D=repeat(C, inner=(1,periodsPerPatch))

  writecsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                  name*".csv"), D)
  return D
end
