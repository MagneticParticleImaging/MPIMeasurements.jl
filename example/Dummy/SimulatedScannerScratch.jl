using MPIMeasurements
using Plots
using Unitful
using UnitfulRecipes

pyplot()
default(show = true)

ENV["JULIA_DEBUG"] = "all"

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "../../test/Scanner/TestConfigs")
addConfigurationPath(testConfigDir)

scannerName_ = "TestSimpleSimulatedScanner"
scanner = MPIScanner(scannerName_)

path = normpath(testConfigDir, "TestSimpleSimulatedScanner/Sequences/Sequence.toml")
sequence = sequenceFromTOML(path)
setupSequence(scanner, sequence)

uMeas, uRef, t = readData(getDAQ(scanner), 1, 5)
# plot(t, uRef[:,1,1,2])
# plot!(t, uMeas[:,1,1,2])
plot(t[:, 1, 2], uRef[:,1,1,2])
