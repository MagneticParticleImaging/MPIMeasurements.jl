#!/usr/bin/env julia
# Quick test to check if Arduino firmware is loaded and responding

using LibSerialPort

println("Testing Arduino at /dev/ttyACM0...")

try
    sp = LibSerialPort.open("/dev/ttyACM0", 74880)
    set_read_timeout(sp, 2000)  # 2 second timeout
    
    println("Serial port opened successfully")
    println("Sending identity query: *IDN?#")
    
    # Send command
    write(sp, "*IDN?#\r")
    sleep(0.5)
    
    # Try to read response
    if bytesavailable(sp) > 0
        response = String(read(sp, bytesavailable(sp)))
        println("✓ Arduino responded: $response")
    else
        println("✗ No response from Arduino")
        println("  The firmware may not be uploaded to the Arduino.")
        println("  Upload the .ino file from:")
        println("  spericalsensor_ba-janne_hamann/communicationSerialWithArduino/serialCommunicationWithJulia/")
    end
    
    close(sp)
catch e
    println("✗ Error: $e")
end
