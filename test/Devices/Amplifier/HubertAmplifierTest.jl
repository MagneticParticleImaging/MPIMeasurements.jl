function deviceTest(device::HubertAmplifier)
    @testset "$(string(typeof(device)))" begin
        if ask_dialog("You are trying to start the Hubert amplifier hardware test. Please ensure that the amp is turned on and a load is connected. Please continue only if the robot is safe to move!", "Cancel", "Start test")
            @error "Hubert amp test has not been implemented yet!"
            @test_broken 0
        
            @test ask_dialog("Did everything seem normal?")
        else
            @test_broken 0
        end        
      end
end