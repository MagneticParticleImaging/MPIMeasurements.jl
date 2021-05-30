using MPIMeasurements
using Plots
using Unitful
using UnitfulRecipes
using UUIDs

pyplot()
default(show = true)

ENV["JULIA_DEBUG"] = "all"

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "../../test/Scanner/TestConfigs")
addConfigurationPath(testConfigDir)

study = MDFv2Study(
  description = "n.a.",
  name = "My simulated study",
  number = 1,
  time = now(),
  uuid = UUIDs.uuid4()
)

experiment = MDFv2Experiment(;
  description = "n.a.",
  isSimulation = true,
  name = "My simulated experiment",
  number = 1,
  subject = "Phantom of the Opera",
  uuid = UUIDs.uuid4()
)

scannerName_ = "TestSimpleSimulatedScanner"
protocolName_ = "SimulatedDAQMeasurement"
filename = joinpath("./tmp.mdf")

protocol = Protocol(protocolName_, scannerName_)
prepareMDF(protocol, study, experiment, filename)
runProtocol(protocol)