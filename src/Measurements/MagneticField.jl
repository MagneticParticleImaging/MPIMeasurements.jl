using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

export saveMagneticFieldAsHDF5, MagneticFieldMeas, getXYZValues, getPosition

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gaussMeter::GaussMeter
  unit::Unitful.FreeUnits
  positions::Vector{Vector{typeof(1.0u"m")}}
  magneticField::Vector{Vector{typeof(1.0u"T")}}
end

# define preMoveAction
function preMoveAction(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")}, index)
  println("moving to next position...")
end

# define postMoveAction
function postMoveAction(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")}, index)
  println("post action: ", pos)
  sleep(0.05)
  getPosition(measObj, pos)
  getXYZValues(measObj)
  println(measObj.magneticField[end])
end

function getXYZValues(measObj::MagneticFieldMeas)
    push!(measObj.magneticField, getXYZValues(measObj.gaussMeter)*measObj.unit)
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

function saveMagneticFieldAsHDF5(measObj::MagneticFieldMeas, filename::String,
        positions, params=Dict{String,Any}())
  h5open(filename, "w") do file
    write(file, positions)
    write(file, "/unitCoords", "m")
    write(file, "/unitFields", "T")
    write(file, "/positions", hcat(ustrip.(measObj.positions)...))
    write(file, "/fields", hcat(ustrip.(measObj.magneticField)...))
    for (key,value) in params
      write(file, key, value)
    end
  end
end

export loadMagneticField
function loadMagneticField(filename::String)
  res = h5open(filename, "r") do file
    positions = Positions(file)
    field = read(file, "/fields")
    return positions, field
  end
  return res
end

# uconvert(u"T", 20u"mT")
