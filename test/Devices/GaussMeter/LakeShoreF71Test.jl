using Gtk
using Sockets
params = LakeShoreF71GaussMeterParams(ip=ip"192.168.2.2", connectionMode=TCP)
gauss = LakeShoreF71GaussMeter(deviceID="lakeshoref71", params=params, dependencies=Dict{String, Union{Device, Missing}}())

if ask_dialog("You are trying to start the LakeShore F71 hardware test. Please ensure that the device is turned on and working.","Cancel","Start test")
	setMeasurementMode(gauss, F71_MM_DC)
	@test ask_dialog("Is the measurement mode set to DC?", "No", "Yes")

	setMeasurementMode(gauss, F71_MM_AC)
	@test ask_dialog("Is the measurement mode set to AC?", "No", "Yes")

	setMeasurementMode(gauss, F71_MM_HIFR)
	@test ask_dialog("Is the measurement mode set to HIFR?", "No", "Yes")

	info_dialog("Please position a magnet near the probe.")

	currentValue = parse(input_dialog("Please enter the current reading of the x-channel.", "")[2])
	@test isapprox(currentValue, ustrip(u"T", getXValue(gauss)), rtol=0.1e-3)

	currentValue = parse(input_dialog("Please enter the current reading of the y-channel.", "")[2])
	@test isapprox(currentValue, ustrip(u"T", getYValue(gauss)), rtol=0.1e-3)

	currentValue = parse(input_dialog("Please enter the current reading of the z-channel.", "")[2])
	@test isapprox(currentValue, ustrip(u"T", getZValue(gauss)), rtol=0.1e-3)

	@test ask_dialog("Is the probe's temperature reading of $(getTemperature(gauss)) °C a probable value?")
	@test ask_dialog("Is the probe's frequency reading of $(getFrequency(gauss)) Hz a probable value?")
	
	@test ask_dialog("Did everything seem normal?")
else
  @test_broken 0
end