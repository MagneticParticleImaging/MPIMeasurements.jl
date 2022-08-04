export SimpleBoreCollisionModule, SimpleBoreCollisionModuleParams

Base.@kwdef struct SimpleBoreCollisionModuleParams <: DeviceParams
  "Diameter of scanner in the y-z plane"
  scannerDiameter::typeof(1.0u"mm")
  "Geometry of the probe, centered at (0,0,0) in scanner coordinates"
  objGeometry::Geometry

  clearance::Clearance = Clearance(1.0u"mm")

  "Define the minimum and maximum points of movement into and out of the bore axis (x)"
  minMaxBoreAxis::Vector{typeof(1.0u"mm")} = [-Inf, Inf]u"mm"
end

SimpleBoreCollisionModuleParams(dict::Dict) = params_from_dict(SimpleBoreCollisionModuleParams, dict)

Base.@kwdef mutable struct SimpleBoreCollisionModule <: AbstractCollisionModule3D
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimpleBoreCollisionModuleParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String,Union{Device,Missing}}
end

collisionModuleType(cm::SimpleBoreCollisionModule) = PositionCollisionType()

function _checkCoordinate(cm::SimpleBoreCollisionModule, pos::AbstractVector{<:Unitful.Length}; returnVerbose=false)
  validStatus = Array{Bool}(undef, 3)
  errorDiff = Array{typeof(1.0u"mm")}(undef, 3)

  validStatus[1], errorDiff[1] = _checkCoordsBoreAxis(cm, pos)
  tmp = _checkCoordsCrossSection(cm, pos)

  errorDiff[2:3] .= tmp[2:3]
  validStatus[2:3] .= tmp[1]

  return validStatus, errorDiff
end

function _checkCoordsBoreAxis(cm::SimpleBoreCollisionModule, pos::AbstractVector{<:Unitful.Length})
  posBore = pos[1]
  if posBore < minimum(cm.params.minMaxBoreAxis)
    return false, posBore - minimum(cm.params.minMaxBoreAxis)
  elseif posBore > maximum(cm.params.minMaxBoreAxis)
    return false, posBore - maximum(cm.params.minMaxBoreAxis)
  else
    return true, zero(0.0u"mm")
  end
end

_checkCoordsCrossSection(cm::SimpleBoreCollisionModule, pos::AbstractVector{<:Unitful.Length}) = checkCollisionYZCircle(cm.params.objGeometry, cm.params.scannerDiameter / 2, pos[2], pos[3], cm.params.clearance.distance)