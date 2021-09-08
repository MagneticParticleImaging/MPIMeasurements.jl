export saveMagneticFieldAsHDF5, MagneticFieldSweepCurrentsMeas

#TODO: Unit handling should be put into GaussMeter

# define measObj
@compat struct MagneticFieldSweepCurrentsMeas <: MeasObj
  su::SurveillanceUnit
  daq::AbstractDAQ
  gauss::GaussMeter
  positions::Positions
  currents::Matrix{Float64}
  gaussRanges::Vector{Int}
  waitTime::Float64
#  voltToCurrent::Float64
  pos::Matrix{typeof(1.0Unitful.m)}
  magneticField::Array{typeof(1.0Unitful.T),3}
  magneticFieldError::Array{typeof(1.0Unitful.T),3}

  MagneticFieldSweepCurrentsMeas(su, daq, gauss, positions, currents, gausMeterRanges, waitTime) =
                 new(su, daq, gauss, positions, currents, gausMeterRanges, waitTime, #voltToCurrent,
                      zeros(typeof(1.0Unitful.m),3,length(positions)),
                      zeros(typeof(1.0Unitful.T),3,length(positions),size(currents,2)),
                      zeros(typeof(1.0Unitful.T),3,length(positions),size(currents,2)))
end

# define preMoveAction
function preMoveAction(measObj::MagneticFieldSweepCurrentsMeas,
                       pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "moving to position" pos
end

# define postMoveAction
function postMoveAction(measObj::MagneticFieldSweepCurrentsMeas,
                        pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "post action" pos index length(measObj.positions)
  #sleep(0.05)
  measObj.pos[:,index] = pos

  for l=1:size(measObj.currents,2)
    # set current at DC sources
    #value(measObj.rp,"AOUT0",measObj.currents[1,l]*measObj.voltToCurrent)
    #value(measObj.rp,"AOUT1",measObj.currents[2,l]*measObj.voltToCurrent)
    setSlowDAC(measObj.daq, measObj.currents[1,l], 0)
    setSlowDAC(measObj.daq, measObj.currents[2,l], 1)

    @debug "Set DC source $(measObj.currents[1,l]*Unitful.A)  $(measObj.currents[2,l]*Unitful.A)"
    # set measurement range of gauss meter
    range = measObj.gaussRanges[l]
    setAllRange(measObj.gauss, Char("$range"[1]))
    # wait until magnet is on field
    sleep(0.6)
    # perform field measurment
    magneticField = getXYZValues(measObj.gauss)
    measObj.magneticField[:,index,l] = magneticField
    # perform error estimation based on gauss meter specification
    magneticFieldError = zeros(typeof(1.0Unitful.T),3,2)
    magneticFieldError[:,1] = abs.(magneticField)*1e-3
    magneticFieldError[:,2] = getFieldError(range).*ones(3)
    measObj.magneticFieldError[:,index,l] = maximum(magneticFieldError,dims=2)

    @info "Field $(uconvert.(Unitful.mT,measObj.magneticField[:,index,l]))"
  end
  setSlowDAC(measObj.daq, 0.0, 0)
  setSlowDAC(measObj.daq, 0.0, 1)

  @showprogress for i=1:measObj.waitTime
    sleep(1)
  end

end

function saveMagneticFieldAsHDF5(measObj::MagneticFieldSweepCurrentsMeas,
       filename::String, params=Dict{String,Any}())
  h5open(filename, "w") do file
    write(file, measObj.positions)
    write(file, "/unitCoords", "m")
    write(file, "/unitFields", "T")
    write(file, "/positions", ustrip.(measObj.pos))
    write(file, "/fields", ustrip.(measObj.magneticField))
    write(file, "/fieldsError", ustrip.(measObj.magneticFieldError))
    write(file, "/currents", measObj.currents)
    for (key,value) in params
      write(file, key, value)
    end
  end
end
