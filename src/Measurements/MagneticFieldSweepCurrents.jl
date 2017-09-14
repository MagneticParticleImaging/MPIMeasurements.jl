using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

export saveMagneticFieldAsHDF5, MagneticFieldSweepCurrentsMeas

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldSweepCurrentsMeas <: MeasObj
  rp::RedPitaya
  gauss::GaussMeter
  unit::Unitful.FreeUnits
  positions::Positions
  currents::Matrix{Float64}
  waitTime::Float64
  voltToCurrent::Float64
  pos::Matrix{typeof(1.0u"m")}
  magneticField::Array{typeof(1.0u"T"),3}

  MagneticFieldSweepCurrentsMeas(rp, gauss, unit, positions, currents, waitTime, voltToCurrent) =
                 new(rp, gauss, unit, positions, currents, waitTime, voltToCurrent,
                      zeros(typeof(1.0u"m"),3,length(positions)),
                      zeros(typeof(1.0u"T"),3,length(positions),size(currents,2)))
end

# define preMoveAction
function preMoveAction(measObj::MagneticFieldSweepCurrentsMeas,
                       pos::Vector{typeof(1.0u"mm")}, index)
  println("moving to next position...")
end

# define postMoveAction
function postMoveAction(measObj::MagneticFieldSweepCurrentsMeas,
                        pos::Vector{typeof(1.0u"mm")}, index)
  println("post action: ", pos)
  sleep(0.05)
  measObj.pos[:,index] = pos

  #println( "Set DC source $newvoltage   $(value(measObj.rp,"AIN2")) " )

  for l=1:size(measObj.currents,2)
    current = measObj.currents[1,l]
    value(measObj.rp,"AOUT0",measObj.currents[1,l]*measObj.voltToCurrent)
    value(measObj.rp,"AOUT1",measObj.currents[2,l]*measObj.voltToCurrent)
    println( "Set DC source $(measObj.currents[1,l])  $(measObj.currents[2,l]) " )
    sleep(0.4) # wait until magnet is on field
    measObj.magneticField[:,index,l] = getXYZValues(measObj.gauss)*measObj.unit
    println(measObj.magneticField[:,index,l])
  end
  value(measObj.rp,"AOUT0",0.0)
  value(measObj.rp,"AOUT1",0.0)

  sleep(measObj.waitTime)

end

#function setRange(measObj::MagneticFieldMeas)
#    r = getRange(measObj.gauss)
#    if r == "0"
#        measObj.unit = u"T"
#    else
#        measObj.unit =  u"mT"
#    end
#end

function saveMagneticFieldAsHDF5(measObj::MagneticFieldSweepCurrentsMeas,
       filename::String, params=Dict{String,Any}())
  h5open(filename, "w") do file
    write(file, measObj.positions)
    write(file, "/unitCoords", "m")
    write(file, "/unitFields", "T")
    write(file, "/positions", ustrip.(measObj.pos))
    write(file, "/fields", ustrip.(measObj.magneticField))
    write(file, "/currents", measObj.currents)
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

    if typeof(positions) == MeanderingGridPositions
      field = field[:,getPermutation(positions),:]
      positions = positions.grid
    end

    return positions, field
  end
  return res
end

# uconvert(u"T", 20u"mT")
