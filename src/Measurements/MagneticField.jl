export saveMagneticFieldAsHDF5, MagneticFieldMeas

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gauss::GaussMeter
  positions::Positions
  gaussRange::Int
  pos::Array{typeof(1.0u"m"),2}
  magneticField::Array{typeof(1.0u"T"),3}
  magneticFieldError::Array{typeof(1.0u"T"),3}
  timestamp::Array{String,2}
  pause::Float64

  MagneticFieldMeas(gauss, positions, gausMeterRange, numMeasPerPos=1, pause=0.0) =
    new(gauss, positions, gausMeterRange,
                   zeros(typeof(1.0u"m"),3,length(positions)),
                   zeros(typeof(1.0u"T"),3,numMeasPerPos,length(positions)),
                   zeros(typeof(1.0u"T"),3,numMeasPerPos,length(positions)),
                   Array{String,2}(numMeasPerPos,length(positions)), pause)
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
  # set measurement range of gauss meter
  range = measObj.gaussRange
  setAllRange(measObj.gauss, Char("$range"[1]))

  for l=1:size(measObj.magneticField,2)
    # perform field measurment
    magneticField = getXYZValues(measObj.gauss)
    measObj.timestamp[l,index] = string(now())
    measObj.magneticField[:,l,index] = magneticField
    # perform error estimation based on gauss meter specification
    magneticFieldError = zeros(typeof(1.0u"T"),3,2)
    magneticFieldError[:,1] = abs.(magneticField)*1e-3
    magneticFieldError[:,2] = getFieldError(range)
    measObj.magneticFieldError[:,l,index] = sum(magneticFieldError,2)

    println(measObj.magneticField[:,l,index])
    sleep(measObj.pause)
  end
end

function saveMagneticFieldAsHDF5(measObj::MagneticFieldMeas,
       filename::String, params=Dict{String,Any}())
  h5open(filename, "w") do file
    write(file, measObj.positions)
    write(file, "/unitCoords", "m")
    write(file, "/unitFields", "T")
    write(file, "/positions", ustrip.(measObj.pos))
    write(file, "/fields", ustrip.(measObj.magneticField))
    write(file, "/fieldsError", ustrip.(measObj.magneticFieldError))
    write(file, "/timestamp", measObj.timestamp )
    for (key,value) in params
      write(file, key, value)
    end
  end
end
