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

study_ = MDFv2Study(
  description = "n.a.",
  name = "My simulated study",
  number = 1,
  time = now(),
  uuid = UUIDs.uuid4()
)

experiment_ = MDFv2Experiment(;
  description = "n.a.",
  isSimulation = true,
  name = "My simulated experiment",
  number = 1,
  subject = "Phantom of the Opera",
  uuid = UUIDs.uuid4()
)

scannerName_ = "DummyScanner"
operator = "Jonas"

protocolName_ = "DummyMeasurement"

cph = ConsoleProtocolHandler(scannerName_, protocolName_)
study(cph, study_)
experiment(cph, experiment_)
startProtocol(sph)

#data = protocol.mdf.measurement.data
#dataRMS = mapslices(x -> sqrt(1/length(x)*sum(x.^2)), data, dims = 1)
#plot(reshape(dataRMS, length(dataRMS)))
#plot(reshape(data, length(data)))