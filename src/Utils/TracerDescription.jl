# Open question: Is this really needed or should be directly use the MDF? This represents single tracers versus the vectors used in the MDF.

Base.@kwdef mutable struct Tracer
  "Batch of tracer"
  batch::Union{String, Missing} = missing
  "A mol(solute)/L no Molar concentration of solute per litre"
  concentration::Union{typeof(1.0u"mol/L"), Missing} = missing
  "UTC time at which tracer injection started; optional"
  injectionTime::Union{DateTime, Nothing} = nothing
  "Name of tracer used in experiment"
  name::Union{String, Missing} = missing
  "Solute, e.g. Fe"
  solute::Union{String, Missing} = missing
  "Name of tracer supplier"
  vendor::Union{String, Missing} = missing
  "Total volume of applied tracer"
  volume::Union{typeof(1.0u"mL"), Missing} = missing
end

function Base.convert(::Type{MDFv2Tracer}, x::Tracer)
  tracer = defaultMDFv2Tracer()
  tracerBatch(tracer, ismissing(x.batch) ? missing : [x.batch])
  tracerConcentration(tracer, ismissing(x.concentration) ? missing : [x.concentration])
  tracerInjectionTime(tracer, isnothing(x.injectionTime) ? nothing : [x.injectionTime])
  tracerName(tracer, ismissing(x.name) ? missing : [x.name])
  tracerSolute(tracer, ismissing(x.solute) ? missing : [x.solute])
  tracerVendor(tracer, ismissing(x.vendor) ? missing : [x.vendor])
  tracerVolume(tracer, ismissing(x.volume) ? missing : [x.volume])

  return tracer
end

function Base.convert(::Type{Tracer}, x::MDFv2Tracer)
  return Tracer(
    batch = tracerBatch(x),
    concentration = tracerConcentration(x),
    injectionTime = tracerInjectionTime(x),
    name = tracerName(x),
    solute = tracerSolute(x),
    vendor = tracerVendor(x),
    volume = tracerVolume(x),
  )
end