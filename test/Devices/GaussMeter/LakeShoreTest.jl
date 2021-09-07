using Gtk
using Sockets
params = LakeShoreGaussMeterParams(ip=ip"192.168.2.2")
gauss = LakeShoreGaussMeter(deviceID="lakeshoref", params=params)

if ask_dialog("You are trying to start the LakeShore gaussmeter hardware test. Please ensure that the device is turned on and working.","Cancel","Start test")
    @error "Not yet implemented!"
    
    
    @test ask_dialog("Did everything seem normal?")
else
    @test_broken 0
end