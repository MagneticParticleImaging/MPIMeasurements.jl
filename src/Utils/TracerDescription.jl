# Open question: Is this really needed or should be directly use the MDF?

Base.@kwdef mutable struct Tracer
  "Batch of tracer"
  batch::Union{String, Missing}
  "A mol(solute)/L no Molar concentration of solute per litre"
  concentration::Union{typeof(1.0u"mol/L"), Missing}
  "UTC time at which tracer injection started; optional"
  injectionTime::Union{DateTime, Nothing}
  "Name of tracer used in experiment"
  name::Union{String, Missing}
  "Solute, e.g. Fe"
  solute::Union{String, Missing}
  "Name of tracer supplier"
  vendor::Union{String, Missing}
  "Total volume of applied tracer"
  volume::Union{typeof(1.0u"mL"), Missing}
end

function Base.convert(::Type{MDFv2Tracer}, x::Tracer)
  error("Not yet implemented!")
end

function Base.convert(::Type{Tracer}, x::MDFv2Tracer)
  error("Not yet implemented!")
end