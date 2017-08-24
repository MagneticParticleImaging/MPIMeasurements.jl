using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gaussMeter::MPIMeasurements.SerialDevice{MPIMeasurements.GaussMeter}
  unit::Unitful.FreeUnits
  positions::Vector{Vector{typeof(1.0u"m")}}
  magneticField::Vector{Vector{typeof(1.0u"T")}}
end

function getXYZValues(measObj::MagneticFieldMeas)
    push!(measObj.magneticField, [getXValue(measObj.gaussMeter), getYValue(measObj.gaussMeter), getZValue(measObj.gaussMeter)]*measObj.unit)
end

function getPosition(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
    push!(measObj.positions, pos)
end

#function setRange(measObj::MagneticFieldMeas)
#    r = getRange(measObj.gaussMeter)
#    if r == "0"
#        measObj.unit = u"T"
#    else
#        measObj.unit =  u"mT"
#    end
#end

function saveMagneticFieldAsHDF5(measObj::MagneticFieldMeas, filename::String, grad)
    h5open(filename, "w") do file
      write(file, "/grad", ustrip(grad))
      write(file, "/unitCoords", "m")
      write(file, "/unitFields", "T")
      write(file, "/coords", hcat(ustrip.(measObj.positions)...))
      write(file, "/fields", hcat(ustrip.(measObj.magneticField)...))
    end
end

# uconvert(u"T", 20u"mT")
