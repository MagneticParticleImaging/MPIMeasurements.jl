"""
Simple script to verify your Porridge field measurement setup

Run this before your first measurement to check that everything is configured correctly.
"""

using MPIMeasurements

println("=" ^ 80)
println("Porridge Field Measurement Setup Verification")
println("=" ^ 80)
println()

# Check 1: Scanner configuration
println("✓ Checking scanner configuration...")
try
    scanner = MPIScanner("PorridgeFieldCamera", robust=false)
    println("  ✓ Scanner 'PorridgeFieldCamera' found")
    
    # Check devices
    try
        fc = getGaussMeter(scanner)
        println("  ✓ Field camera configured: $(typeof(fc))")
        println("    - Port: $(fc.params.portAddress)")
        println("    - Range: $(fc.params.measurementRange)mT")
        println("    - Sensors: $(fc.params.numSensors)")
    catch e
        println("  ✗ Field camera not found: $e")
    end
    
    try
        daq = getDAQ(scanner)
        println("  ✓ DAQ configured: $(typeof(daq))")
    catch e
        println("  ✗ DAQ not found: $e")
    end
    
    close(scanner)
catch e
    println("  ✗ Scanner configuration error: $e")
    println()
    println("To fix:")
    println("  1. Check that config/PorridgeFieldCamera/Scanner.toml exists")
    println("  2. Verify the file has correct syntax")
    exit(1)
end

println()

# Check 2: Protocol configuration
println("✓ Checking protocol configuration...")
try
    scanner = MPIScanner("PorridgeFieldCamera", robust=false)
    protocol = Protocol("PorridgeFieldMeasurement", scanner)
    println("  ✓ Protocol 'PorridgeFieldMeasurement' found")
    println("    - Description: $(description(protocol))")
    if !isnothing(protocol.params.sequence)
        println("    - Sequence: $(protocol.params.sequence.general.name)")
    end
    println("    - Measurements per point: $(protocol.params.numMeasurementsPerPoint)")
    close(scanner)
catch e
    println("  ✗ Protocol configuration error: $e")
    println()
    println("To fix:")
    println("  1. Check that config/PorridgeFieldCamera/Protocols/PorridgeFieldMeasurement.toml exists")
    println("  2. Verify sequence file exists if specified")
    exit(1)
end

println()

# Check 3: Device connection (optional - might not be connected yet)
println("✓ Checking device connections...")
println("  (Optional - devices may not be connected during setup)")

try
    scanner = MPIScanner("PorridgeFieldCamera", robust=true)
    
    # Try to get field camera
    fc = getGaussMeter(scanner)
    println("  ✓ Field camera initialized successfully")
    println("    - Device ready for measurements")
    
    close(scanner)
catch e
    println("  ⚠ Field camera initialization failed: $e")
    println()
    println("This is normal if:")
    println("  1. Arduino is not connected yet")
    println("  2. COM port in Scanner.toml is incorrect")
    println("  3. Another program is using the serial port")
    println()
    println("To fix:")
    println("  1. Connect the Arduino field camera")
    println("  2. Find the correct COM port:")
    println("     - Windows: Check Device Manager → Ports")
    println("     - Linux: Run 'ls /dev/ttyUSB*' or 'ls /dev/ttyACM*'")
    println("     - Mac: Run 'ls /dev/tty.usb*'")
    println("  3. Update portAddress in config/PorridgeFieldCamera/Scanner.toml")
end

println()
println("=" ^ 80)
println("Setup Verification Complete!")
println("=" ^ 80)
println()
println("Next steps:")
println("  1. If all checks passed: Run example/PorridgeFieldMeasurementExample.jl")
println("  2. If device connection failed: Connect hardware and update COM port")
println("  3. For quick start: See QUICKSTART_FIELD_MEASUREMENTS.md")
println("  4. For full documentation: See docs/PorridgeFieldMeasurement.md")
println()
