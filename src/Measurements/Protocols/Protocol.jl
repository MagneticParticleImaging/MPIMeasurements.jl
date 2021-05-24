struct Action
  call::Symbol
  parameters::Dict{Symbol, Any}
end

struct Step
  id::AbstractString
  nextStepID::AbstractString
  actions::Vector{Action}
end

struct Protocol
  name::AbstractString
  description::AbstractString
  targetScanner::AbstractString
  steps::Vector{Step}
  variables::Dict{String, Any}
  #results:: # Ergebnisse von Steps die nachfolgenden Steps zur Verfügung stehen sollen bspw. Daten der Empfangskanäle oder Magnetfeldmessungen
end

#protocolFromDict()