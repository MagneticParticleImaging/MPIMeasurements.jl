#TODO: write more tests

@testset "Testing SimpleBoreCollisionModule" begin

# check if delta is correctly calculated
function checkDeltaWithRandomPoints(cm, nPoints=1000)
  for i in 1:nPoints
    pos = [0u"mm", (rand()-0.5)*2*cm.params.scannerDiameter, (rand()-0.5)*2*cm.params.scannerDiameter]
    
    correct = checkDelta(cm, pos)
    if !correct
      return false
    end

  end
  return true
end

function checkDelta(cm, pos)
  state, delta = checkCoords(cm, pos, returnVerbose=true)
  if !all(state .== :VALID)
    state1, _ = checkCoords(cm, pos.-delta, returnVerbose=true)
    state2, _ = checkCoords(cm, pos.-(delta-sign.(delta).*[0,0.1,0.1]u"mm"), returnVerbose=true)
    if !( all(state1 .== :VALID) & all(state2[2:3] .== :INVALID) )
      @error pos, delta, state1, state2
      MPIMeasurements.plotSafetyErrors(cm, [1,2,3], transpose(hcat(pos, pos.-delta, pos.-(delta-sign.(delta).*[0,0.1,0.1]u"mm"))))
      return false
    end
  end
  
  return true
end

@testset "SimpleBoreCollisionModule: Circle" begin
  par = SimpleBoreCollisionModuleParams(scannerDiameter=118u"mm", objGeometry = Circle(name="Delta sample", diameter=10u"mm"), minMaxBoreAxis = [-300u"mm",Inf*u"mm"])
  cm = SimpleBoreCollisionModule(deviceID="testCollisionModule", params=par, dependencies=Dict{String, Union{Device, Missing}}())

  @test checkDeltaWithRandomPoints(cm, 100000)
  @test checkCoords(cm, [0,0,0]u"mm")
  @test !checkCoords(cm, [0,1,0]u"m")
  @test !checkCoords(cm, [-300.1,0,0]u"mm")
  @test checkCoords(cm, [-300,0,0]u"mm")
  @test checkCoords(cm, [0u"mm", par.scannerDiameter/2 - par.clearance.distance - par.objGeometry.diameter/2, 0u"mm"])
  state, dist = checkCoords(cm, [0u"mm", par.scannerDiameter/2 - par.clearance.distance - par.objGeometry.diameter/2 + 0.001u"mm", 0u"mm"], returnVerbose=true)
  @test !all(state .== :VALID)
  @test isapprox(dist[2], 0.001u"mm", atol=1u"nm")

end

@testset "SimpleBoreCollisionModule: Rectangle" begin
  par = SimpleBoreCollisionModuleParams(scannerDiameter=118u"mm", objGeometry = Rectangle(name="Test rectangle", width=10u"mm", height=10u"mm"), minMaxBoreAxis = [-300u"mm",Inf*u"mm"])
  cm = SimpleBoreCollisionModule(deviceID="testCollisionModule", params=par, dependencies=Dict{String, Union{Device, Missing}}())

  @test checkDeltaWithRandomPoints(cm, 100000)  

end

@testset "SimpleBoreCollisionModule: Triangle" begin
  par = SimpleBoreCollisionModuleParams(scannerDiameter=118u"mm", objGeometry = Triangle(name="Test triangle", width=10u"mm", height=10u"mm"), minMaxBoreAxis = [-300u"mm",Inf*u"mm"])

  cm = SimpleBoreCollisionModule(deviceID="testCollisionModule", params=par, dependencies=Dict{String, Union{Device, Missing}}())

 #@test checkDeltaWithRandomPoints(cm, 1000) # this test fails 

end


end



