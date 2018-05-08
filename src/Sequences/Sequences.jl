export makeSequence

#6.312341575312002
#13.705627903244254


function makeSequence(name::String, minCurr, maxCurr, patches, periodsPerPatch)
  A=linspace(minCurr,maxCurr,patches)
  C = cat(1,A',flipdim(A',2))
  B=repeat(cat(2,C,flipdim(C,2)), inner=(1,periodsPerPatch))
  writecsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                  name*".csv"), B)
  return B
end
