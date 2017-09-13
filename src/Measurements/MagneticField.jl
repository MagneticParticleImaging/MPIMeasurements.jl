using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

export saveMagneticFieldAsHDF5, MagneticFieldMeas

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gauss::GaussMeter
  unit::Unitful.FreeUnits
  positions::Positions
  pos::Matrix{typeof(1.0u"m")}
  magneticField::Matrix{typeof(1.0u"T")}

  MagneticFieldMeas(gauss, unit, positions) =
    new(gauss, unit, positions, zeros(typeof(1.0u"m"),3,length(positions))
                                 , zeros(typeof(1.0u"T"),3,length(positions)))
end

# define preMoveAction
function preMoveAction(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")}, index)
  println("moving to next position...")
end

# define postMoveAction
function postMoveAction(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")}, index)
  println("post action: ", pos)
  sleep(0.05)
  measObj.pos[:,index] = pos
  measObj.magneticField[:,index] = getXYZValues(measObj.gauss)*measObj.unit
  println(measObj.magneticField[:,index])
end

#function setRange(measObj::MagneticFieldMeas)
#    r = getRange(measObj.gauss)
#    if r == "0"
#        measObj.unit = u"T"
#    else
#        measObj.unit =  u"mT"
#    end
#end

function saveMagneticFieldAsHDF5(measObj::MagneticFieldMeas,
       filename::String, params=Dict{String,Any}())
  h5open(filename, "w") do file
    write(file, measObj.positions)
    write(file, "/unitCoords", "m")
    write(file, "/unitFields", "T")
    write(file, "/positions", ustrip.(measObj.pos))
    write(file, "/fields", ustrip.(measObj.magneticField))
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
