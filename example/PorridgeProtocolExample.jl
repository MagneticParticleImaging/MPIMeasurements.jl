# Example script for using the Porridge Protocol for ML data generation
# This script demonstrates how to run the protocol to generate training data

using MPIMeasurements

# Initialize the scanner
scanner = MPIScanner("Porridge")

# Load the Porridge protocol
protocol = Protocol("Porridge", scanner)

# Initialize the protocol
init(protocol)

# Check the time estimate
println("Estimated measurement time: ", timeEstimate(protocol))

# Run the protocol (this would be done through the normal measurement interface)
# execute(protocol)

# The protocol will:
# 1. Use the current sequences directly from the Porridge.toml configuration matrix
# 2. The matrix has 5 rows (sequence steps) × 18 columns (coils)
# 3. Measure magnetic fields with the MagSphere for each sequence step:
#    - Step 1: All coils at 0.01A (first row of matrix)
#    - Step 2: All coils at 0.02A (second row of matrix)
#    - Step 3: All coils at 0.03A (third row of matrix)  
#    - Step 4: All coils at 0.04A (fourth row of matrix)
#    - Step 5: All coils at 0.05A (fifth row of matrix)
# 4. Store the results in HDF5 format with sequence-to-field mappings for ML training

println("Protocol ready. Configured for $(protocol.sequenceLength) sequence measurements.")
println("Each measurement will have:")
println("- Magnetic field data from 86 MagSphere sensors")
println("- Current values for all 18 coils at that sequence step")
println("- Timestamp information")
println("- Calibration data")
