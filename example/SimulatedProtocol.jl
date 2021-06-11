using MPIMeasurements
using Plots
using Unitful
using UnitfulRecipes
using UUIDs

#pyplot()
#plotly()
#inspectdr()
default(show = true)

ENV["JULIA_DEBUG"] = "all"

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "../test/TestConfigs")
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
operator = "Jonas"
filename = joinpath("./tmp.mdf")

protocol = Protocol(protocolName_, scannerName_)
prepareMDF(protocol, filename, study, experiment, operator)
runProtocol(protocol)

data = protocol.mdf.measurement.data
#dataRMS = mapslices(x -> sqrt(1/length(x)*sum(x.^2)), data, dims = 1)
#plot(reshape(dataRMS, length(dataRMS)))
#plot(reshape(data, length(data)))