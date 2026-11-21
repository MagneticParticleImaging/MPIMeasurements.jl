@testset "TxDAQController construction" begin
  txParams = TxDAQControllerParams(phaseAccuracy=0.01u"rad", relativeAmplitudeAccuracy=0.01)
  txCont = TxDAQController(deviceID="txCont", params=txParams, dependencies=Dict{String, Union{Device, Missing}}())
  @test isempty(txCont.controlResults)
  @test isnothing(MPIMeasurements.resetCachedCalibration(txCont))
  @test isempty(txCont.controlResults)
end
