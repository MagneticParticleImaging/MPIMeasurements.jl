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


function plotSafetyErrors(cm::SimpleBoreCollisionModule, errorIndices::Vector{Int}, coords::AbstractMatrix{<:Unitful.Length})
  geo = cm.params.objGeometry;
  scannerRad = cm.params.scannerDiameter / 2;
  
  t = range(0, stop=2, length=200);

  x_scanner = scannerRad * cos.(t * pi);
  y_scanner = scannerRad * sin.(t * pi);
  x_scanner2 = (scannerRad - cm.params.clearance.distance) * cos.(t * pi);
  y_scanner2 = (scannerRad - cm.params.clearance.distance) * sin.(t * pi);
  
  fig = plot(title="Plot results - $(geo.name) positions", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal)
  plot!(ustrip.(u"mm", x_scanner), ustrip.(u"mm", y_scanner), color=:blue, label="scanner")
  plot!(ustrip.(u"mm", x_scanner2), ustrip.(u"mm", y_scanner2), color=:yellow, label="scanner, with clearance")
  for i = errorIndices
    y_i = coords[i, 2];
    z_i = coords[i, 3];
    

    if typeof(geo) == Circle
      x_geometry = geo.diameter / 2 * cos.(t * pi) .+ y_i;
      y_geometry = geo.diameter / 2 * sin.(t * pi) .+ z_i;
      
      plot!(ustrip.(u"mm", x_geometry), ustrip.(u"mm", y_geometry), color=:red)

    elseif typeof(geo) == Rectangle
      # Create rectangle corner points
      # point bottom left
      p_bl = ustrip.(u"mm", [y_i - geo.width / 2, z_i - geo.height / 2]);
      # point upper left
      p_ul = ustrip.(u"mm", [y_i - geo.width / 2, z_i + geo.height / 2]);
      # point upper right
      p_ur = ustrip.(u"mm", [y_i + geo.width / 2, z_i + geo.height / 2]);
      # point bottom right
      p_br = ustrip.(u"mm", [y_i + geo.width / 2, z_i - geo.height / 2]);

      rect = transpose([p_bl p_ul p_ur p_br p_bl])
      plot!(rect[:,1], rect[:,2], color=:red);
      
    elseif typeof(geo) == Triangle
      # Create triangle corner points
      # point bottom left
      p_bl = ustrip.(u"mm", [y_i - geo.width / 2, z_i - geo.height / 3]);
      # upper point
      p_u = ustrip.(u"mm", [y_i, z_i + 2 / 3 * geo.height]);
      # point bottom right
      p_br = ustrip.(u"mm", [y_i + geo.width / 2, z_i - geo.height / 3]);

      tri = [p_bl p_u p_br p_bl]
      plot!(tri[1,:], tri[2,:], color=:red, label=nothing);
    end
    
  end
  display(fig)
end