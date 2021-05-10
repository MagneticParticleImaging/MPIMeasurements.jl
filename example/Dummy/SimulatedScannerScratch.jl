using MPIMeasurements
using Plots
using Unitful
using UnitfulRecipes

pyplot()
default(show = true)

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "../../test/Scanner/TestConfigs")
addConfigurationPath(testConfigDir)

scannerName_ = "TestSimpleSimulatedScanner"
scanner = MPIScanner(scannerName_)

path = normpath(testConfigDir, "TestSimpleSimulatedScanner/Sequences/Sequence.toml")
sequence = sequenceFromTOML(path)
setupSequence(scanner, sequence)

uMeas, uRef = readData(getDAQ(scanner), 1, 2)
plot(uRef[:,1,1,2])
plot!(uMeas[:,1,1,2])