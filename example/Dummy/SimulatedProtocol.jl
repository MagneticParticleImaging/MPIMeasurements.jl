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
protocolName_ = "SimulatedDAQMeasurement"

protocol = Protocol(protocolName_, scannerName_)
runProtocol(protocol)
