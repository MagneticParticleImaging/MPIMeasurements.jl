#!/usr/bin/env julia
# Test the actual sensor query command format

using LibSerialPort

println("Testing sensor query commands...")

sp = LibSerialPort.open("/dev/ttyACM0", 74880)
set_read_timeout(sp, 3000)  # 3 second timeout

# First initialize sensors
println("\n1. Initializing all sensors...")
write(sp, "*INITALLSENSORS!>0x0#\r")  # 0x0 = 150mT range
sleep(2.0)  # Give it time to initialize all 37 sensors

if bytesavailable(sp) > 0
    response = String(read(sp, bytesavailable(sp)))
    println("   Response: $response")
end

# Now try to query a sensor
println("\n2. Querying sensor on pin 2...")
write(sp, "*GETFIELDVALUEALLFROMCHIP!>2#\r")
sleep(0.5)

if bytesavailable(sp) > 0
    response = String(read(sp, bytesavailable(sp)))
    println("   Response: $response")
    # Parse response
    if occursin(',', response)
        vals = split(strip(response), ',')
        println("   Field values: X=$(vals[1]) mT, Y=$(vals[2]) mT, Z=$(vals[3]) mT")
    end
else
    println("   ✗ No response")
end

close(sp)
