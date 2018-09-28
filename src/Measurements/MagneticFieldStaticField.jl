export saveMagneticFieldAsHDF5, MagneticFieldStaticField

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldStaticField <: MeasObj
  gauss::GaussMeter
  positions::Positions
  gaussRanges::Vector{Int}
  waitTime::Float64
  pos::Matrix{typeof(1.0Unitful.m)}
  magneticField::Array{typeof(1.0Unitful.T),2}
  magneticFieldError::Array{typeof(1.0Unitful.T),2}

  MagneticFieldStaticField(gauss, positions, gausMeterRanges, waitTime) =
                 new(gauss, positions, gausMeterRanges, waitTime,
                      zeros(typeof(1.0Unitful.m),3,length(positions)),
                      zeros(typeof(1.0Unitful.T),3,length(positions)),
                      zeros(typeof(1.0Unitful.T),3,length(positions)))
end

# define preMoveAction
function preMoveAction(measObj::MagneticFieldStaticField,
                       pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "moving to position" pos
end

# define postMoveAction
function postMoveAction(measObj::MagneticFieldStaticField,
                        pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "post action" index length(measObj.positions)
  #sleep(0.05)
  measObj.pos[:,index] = pos

  @debug "Set DC source $newvoltage   $(value(measObj.rp,"AIN2")) "


    # set current at DC sources
    #value(measObj.rp,"AOUT0",measObj.currents[1,l]*measObj.voltToCurrent)
    #value(measObj.rp,"AOUT1",measObj.currents[2,l]*measObj.voltToCurrent)
    # setSlowDAC(measObj.daq, measObj.currents[1,l]*measObj.voltToCurrent, 0)
    # setSlowDAC(measObj.daq, measObj.currents[2,l]*measObj.voltToCurrent, 1)

    @debug "Set DC source $(measObj.currents[1,l]*Unitful.A)  $(measObj.currents[2,l]*Unitful.A)"
    # set measurement range of gauss meter
    range = measObj.gaussRanges[1]
    setAllRange(measObj.gauss, Char("$range"[1]))
    # wait until magnet is on field
    sleep(0.6)
    # perform field measurment
    magneticField = getXYZValues(measObj.gauss)
    measObj.magneticField[:,index] = magneticField
    # perform error estimation based on gauss meter specification
    magneticFieldError = zeros(typeof(1.0Unitful.T),3,2)
    magneticFieldError[:,1] = abs.(magneticField)*1e-3
    magneticFieldError[:,2] = getFieldError(range)
    measObj.magneticFieldError[:,index] = maximum(magneticFieldError,2)

    @debug "Field $(uconvert.(Unitful.mT,measObj.magneticField[:,index]))"

  # setSlowDAC(measObj.daq, 0.0, 0)
  # setSlowDAC(measObj.daq, 0.0, 1)

  sleep(measObj.waitTime)

end

function saveMagneticFieldAsHDF5(measObj::MagneticFieldStaticField,
       filename::String, params=Dict{String,Any}())
  h5open(filename, "w") do file
    write(file, measObj.positions)
    write(file, "/unitCoords", "m")
    write(file, "/unitFields", "T")
    write(file, "/positions", ustrip.(measObj.pos))
    write(file, "/fields", ustrip.(measObj.magneticField))
    write(file, "/fieldsError", ustrip.(measObj.magneticFieldError))
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
