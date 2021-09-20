using Gtk
using Sockets
params = LakeShoreF71GaussMeterParams(comport="COM4", connectionMode=F71_CM_USB, measurementMode=F71_MM_DC)
gauss = LakeShoreF71GaussMeter(deviceID="lakeshoref71", params=params, dependencies=Dict{String, Union{Device, Missing}}())

if ask_dialog("You are trying to start the LakeShore F71 hardware test. Please ensure that the device is turned on and working.","Cancel","Start test")
	init(gauss)

	setMeasurementMode(gauss, F71_MM_AC)
	@test ask_dialog("Is the measurement mode set to AC?", "No", "Yes")

	setMeasurementMode(gauss, F71_MM_HIFR)
	@test ask_dialog("Is the measurement mode set to HIFR?", "No", "Yes")

	setMeasurementMode(gauss, F71_MM_DC)
	@test ask_dialog("Is the measurement mode set to DC?", "No", "Yes")

	info_dialog("Please position a magnet near the probe.")

	currentValue = uparse(input_dialog("Please enter the current reading of the x-channel (including the unit and without a space).", "")[2])
	@test isapprox(currentValue, getXValue(gauss), rtol=0.1)

	currentValue = uparse(input_dialog("Please enter the current reading of the y-channel (including the unit and without a space).", "")[2])
	@test isapprox(currentValue, getYValue(gauss), rtol=0.1)

	currentValue = uparse(input_dialog("Please enter the current reading of the z-channel (including the unit and without a space).", "")[2])
	@test isapprox(currentValue, getZValue(gauss), rtol=0.1)

	@test ask_dialog("Is the probe's temperature reading of $(getTemperature(gauss)) a probable value?")
	@test ask_dialog("Is the probe's frequency reading of $(getFrequency(gauss)) a probable value?")
	
	@test ask_dialog("Did everything seem normal?")
else
  @test_broken 0
end