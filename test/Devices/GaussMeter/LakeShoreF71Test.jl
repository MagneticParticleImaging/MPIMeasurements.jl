using Gtk
using Sockets
params = LakeShoreF71GaussMeterParams(ip=ip"192.168.2.2")
gauss = LakeShoreF71GaussMeter(deviceID="lakeshoref71", params=params, dependencies=Dict{String, Union{Device, Missing}}())

if ask_dialog("You are trying to start the LakeShore F71 hardware test. Please ensure that the device is turned on and working.","Cancel","Start test")
    # Werte abfragen und dann vergleichen
    
    
    @test ask_dialog("Did everything seem normal?")
else
    @test_broken 0
end