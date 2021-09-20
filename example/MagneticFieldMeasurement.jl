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

scannerName_ = "MagneticFieldMeasurement"
protocolName_ = "MagneticFieldMeasurement"
operator = "Jonas"
filename_ = joinpath("./field.h5")

protocol = Protocol(protocolName_, scannerName_)
filename(protocol, filename_)
runProtocol(protocol)

