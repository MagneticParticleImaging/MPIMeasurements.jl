using MPIMeasurements
using Plots
using Unitful
using UnitfulRecipes
using Dates
using UUIDs

#pyplot()
#plotly()
#inspectdr()
default(show = true)

ENV["JULIA_DEBUG"] = "all"

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "../test/TestConfigs")
addConfigurationPath(testConfigDir)

scannerName_ = "TestSimpleSimulatedScanner"
protocolName_ = "SimulatedMagneticFieldMeasurement"
operator = "Jonas"
filename_ = joinpath("./field.h5")

protocol = Protocol(protocolName_, scannerName_)
filename(protocol, filename_)
runProtocol(protocol)
