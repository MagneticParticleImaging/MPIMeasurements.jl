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

measurement_ = MagneticFieldMeasurement(filename_)

result = zeros(shape(measurement_.positions)...)
for pos in measurement_.positions
  idx = posToLinIdx(measurement_.positions, pos)
  field = norm(measurement_.fields[idx])
  result[posToIdx(measurement_.positions, pos)...] = ustrip(u"mT", field)
end
result = dropdims(result, dims=2)

heatmap(result)