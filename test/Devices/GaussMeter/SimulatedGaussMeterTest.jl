params = SimulatedGaussMeterParams()
gauss = SimulatedGaussMeter(deviceID="simulated_gaussmeter", params=params, dependencies=Dict{String, Union{Device, Missing}}())

@test gauss isa SimulatedGaussMeter
@test getXValue(gauss) == 1.0u"mT"
@test getYValue(gauss) == 2.0u"mT"
@test getZValue(gauss) == 3.0u"mT"
@test getXYZValues(gauss) == [1.0, 2.0, 3.0]u"mT"
