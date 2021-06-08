export saveMagneticFieldAsHDF5, MagneticFieldMeas

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  gauss::GaussMeter
  positions::Positions
  gaussRange::Int
  pos::Array{typeof(1.0Unitful.m),2}
  magneticField::Array{typeof(1.0Unitful.T),3}
  magneticFieldError::Array{typeof(1.0Unitful.T),3}
  timestamp::Array{String,2}
  pause::Float64

  MagneticFieldMeas(gauss, positions, gausMeterRange, numMeasPerPos=1, pause=0.0) =
    new(gauss, positions, gausMeterRange,
                   zeros(typeof(1.0Unitful.m),3,length(positions)),
                   zeros(typeof(1.0Unitful.T),3,numMeasPerPos,length(positions)),
                   zeros(typeof(1.0Unitful.T),3,numMeasPerPos,length(positions)),
                   Array{String,2}(undef,numMeasPerPos,length(positions)), pause)
end

# define preMoveAction
function preMoveAction(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "moving to position" pos
end

# define postMoveAction
function postMoveAction(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "post action"
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
    magneticFieldError = zeros(typeof(1.0Unitful.T),3,2)
    magneticFieldError[:,1] = abs.(magneticField)*1e-3
    magneticFieldError[:,2] .= getFieldError(range)
    measObj.magneticFieldError[:,l,index] = sum(magneticFieldError, dims=2)

    @info "Field $(measObj.magneticField[:,l,index])"
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