export MagneticField
"""
Description of a magnetic field.

The field can either be electromagnetically or mechanically changed.
The mechanical movement of e.g. an iron yoke would be defined within
two channels, one electrical and one mechanical.
"""
Base.@kwdef struct MagneticField
  "Unique ID of the field description."
  id::AbstractString
  "Transmit channels that are used for the field."
  channels::Vector{TxChannel}

  "Flag if the start of the field should be convoluted.
  If the DAQ does not support this, it can may fall back
  to postponing the application of the settings.
  Not used for mechanical fields."
  safeStartInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if a transition of the field should be convoluted.
  If the DAQ does not support this, it can may fall back
  to postponing the application of the settings.
  Not used for mechanical fields."
  safeTransitionInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if the end of the field should be convoluted. In case of an existing brake on
  a mechanical channel this means a use of the brake."
  safeEndInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if the field should be convoluted down in case of an error. In case of an
  existing brake on a mechanical channel this means a use of the brake."
  safeErrorInterval::typeof(1.0u"s") = 0.5u"s"

  "Flag if the channels of the field should be controlled."
  control::Bool = true
  "Flag if the field should be decoupled. Not used for mechanical channels."
  decouple::Bool = true
end

id(field::MagneticField) = field.id

export channels
channels(field::MagneticField) = field.channels
channels(field::MagneticField, T::Type{<:TxChannel}) = [channel for channel in channels(field) if typeof(channel) <: T]

export safeStartInterval
safeStartInterval(field::MagneticField) = field.safeStartInterval
export safeTransitionInterval
safeTransitionInterval(field::MagneticField) = field.safeTransitionInterval
export safeEndInterval
safeEndInterval(field::MagneticField) = field.safeEndInterval
export safeErrorInterval
safeErrorInterval(field::MagneticField) = field.safeErrorInterval

control(field::MagneticField) = field.control
decouple(field::MagneticField) = field.decouple

export electricalTxChannels
electricalTxChannels(field::MagneticField) = channels(field, ElectricalTxChannel)

export mechanicalTxChannels
mechanicalTxChannels(field::MagneticField) = channels(field, MechanicalTxChannel)

export periodicElectricalTxChannels
periodicElectricalTxChannels(field::MagneticField) = channels(field, PeriodicElectricalChannel)

export acyclicElectricalTxChannels
acyclicElectricalTxChannels(field::MagneticField) = channels(field, AcyclicElectricalTxChannel)

function toDict!(dict, field::MagneticField)
  for structField in [x for x in fieldnames(typeof(field)) if !in(x, [:id, :channels])]
    dict[String(structField)] = toDictValue(getproperty(field, structField))
  end
  for channel in channels(field)
    dict[id(channel)] = toDictValue(channel)
  end
  return dict
end

toDictValue(field::MagneticField) = toDict(field)

function toDict!(dict, fields::Vector{MagneticField})
  for field in fields
    dict[id(field)] = toDictValue(field)
  end
  return dict
end