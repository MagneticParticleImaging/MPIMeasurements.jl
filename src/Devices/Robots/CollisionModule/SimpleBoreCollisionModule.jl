using Plots

export SimpleBoreCollisionModule, SimpleBoreCollisionModuleParams

export Geometry, Circle, Rectangle, Triangle
abstract type Geometry end
@mustimplement name(geometry::Geometry)

Base.@kwdef struct SimpleBoreCollisionModuleParams <: DeviceParams
  "Diameter of scanner in the y-z plane"
  scannerDiameter::typeof(1.0u"mm") = Inf * u"mm"
  "Geometry of the probe, centered at (0,0,0) in scanner coordinates"
  objGeometry::Union{Nothing,Geometry} = nothing

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

function _checkCoordinate(cm::SimpleBoreCollisionModule, pos::AbstractVector{<:Unitful.Length}; returnVerbose=false)
  if cm.params.objGeometry === nothing || cm.params.scannerDiameter == Inf * u"mm"
    error("Incomplete definition of SimpleBoreCollisionModule! Please check the definition of objGeometry and scannerDiameter.")
  end

  errorStatus = Array{Symbol}(undef, 3)
  errorDiff = Array{typeof(1.0u"mm")}(undef, 3)

  errorStatus[1], errorDiff[1] = _checkCoordsBoreAxis(cm, pos)
  tmp = _checkCoordsCrossSection(cm, pos)

  errorDiff[2:3] .= tmp[2:3]
  errorStatus[2:3] .= tmp[1]

  return errorStatus, errorDiff
end

struct Circle <: Geometry
  diameter::typeof(1.0Unitful.mm)
  name::String

  function Circle(;diameter::Unitful.Length, name::String)
    if diameter < 1.0Unitful.mm
      error("Circle is too small")
    else
      new(diameter, name)
    end
  end
end

name(geometry::Circle) = geometry.name
Circle(dict::Dict) = params_from_dict(Circle, dict)

struct Rectangle <: Geometry
  width::typeof(1.0Unitful.mm)
  height::typeof(1.0Unitful.mm)
  name::String

  function Rectangle(;width::Unitful.Length, height::Unitful.Length, name::String)
    if width < 1.0Unitful.mm || height < 1.0Unitful.mm
      error("Rectangle is too small")
    else
      new(width, height, name)
    end
  end
end
name(geometry::Rectangle) = geometry.name
Rectangle(dict::Dict) = params_from_dict(Rectangle, dict)

struct Triangle <: Geometry
  width::typeof(1.0Unitful.mm)
  height::typeof(1.0Unitful.mm)
  name::String

  function Triangle(;width::Unitful.Length, height::Unitful.Length, name::String)
    if width < 1.0Unitful.mm || height < 1.0Unitful.mm
      error("Triangle does not fit in scanner...")
    else
      new(width, height, name)
    end
  end
end
name(geometry::Triangle) = geometry.name
Triangle(dict::Dict) = params_from_dict(Triangle, dict)


Geometry(dict::Dict) = params_from_dict(eval(Symbol(pop!(dict,"type"))), dict)
convert(::Type{Geometry}, dict::Dict) = Geometry(dict)

function _checkCoordsBoreAxis(cm::SimpleBoreCollisionModule, pos::AbstractVector{<:Unitful.Length})
  posBore = pos[1]
  if posBore < minimum(cm.params.minMaxBoreAxis)
    return :INVALID, posBore - minimum(cm.params.minMaxBoreAxis)
  elseif posBore > maximum(cm.params.minMaxBoreAxis)
    return :INVALID, posBore - maximum(cm.params.minMaxBoreAxis)
  else
    return :VALID, zero(0.0u"mm")
  end
end

_checkCoordsCrossSection(cm::SimpleBoreCollisionModule, pos::AbstractVector{<:Unitful.Length}) = _checkCoordsGeometry(cm.params.objGeometry, cm.params.scannerDiameter / 2, pos[2], pos[3], cm.params.clearance)
@mustimplement _checkCoordsGeometry(geo::Geometry, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Clearance)

function _checkCoordsGeometry(geo::Circle, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Clearance)
  r = sqrt(posY^2 + posZ^2)

  if scannerRad - clearance.distance >= r + geo.diameter / 2
    return :VALID, zero(0.0u"mm"), zero(0.0u"mm")
  else
    delta_r = r - (scannerRad - clearance.distance)
    delta_y1 = (delta_r+geo.diameter/2) * posY/r
    delta_z1 = (delta_r+geo.diameter/2) * posZ/r
    return :INVALID, 1.0001*delta_y1, 1.0001*delta_z1
  end 
end

function _checkCoordsGeometry(geo::Rectangle, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Clearance)
  corners = [ [posY - geo.width / 2 posZ - geo.height / 2]
              [posY - geo.width / 2 posZ + geo.height / 2]
              [posY + geo.width / 2 posZ + geo.height / 2]
              [posY + geo.width / 2 posZ - geo.height / 2] ];

  dist = norm.(eachrow(corners))
  if all(dist .< (scannerRad - clearance.distance))
    return :VALID, zero(0.0u"mm"), zero(0.0u"mm")
  else
    maxdist, maxidx = findmax(dist)
    delta = maxdist - (scannerRad - clearance.distance)
    if abs(posY) < geo.width/2 + 1u"mm"
      return :INVALID, 0.0u"mm", (corners[maxidx,2] - sign(corners[maxidx,2])*sqrt((scannerRad-clearance.distance)^2-(1.0001*corners[maxidx,1])^2))
    end
    if abs(posZ) < geo.height/2 + 1u"mm"
      return :INVALID, (corners[maxidx,1] - sign(corners[maxidx,1])*sqrt((scannerRad-clearance.distance)^2-(1.0001*corners[maxidx,2])^2)), 0.0u"mm"
    end

    return :INVALID, 1.0001*delta * corners[maxidx,1] / maxdist, 1.0001*delta * corners[maxidx,2] / maxdist
  end
end

function _checkCoordsGeometry(geo::Triangle, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Clearance)
  # following code only for symmetric triangles / center of gravity = center of plug adapter

  corners = [ [posY   posZ + 2/3 * geo.height]
              [posY-geo.width/2   posZ - 1/3 * geo.height]
              [posY+geo.width/2   posZ - 1/3 * geo.height] ];

  dist = norm.(eachrow(corners))
  if all(dist .< (scannerRad - clearance.distance))
    return :VALID, zero(0.0u"mm"), zero(0.0u"mm")
  else
    maxdist, maxidx = findmax(dist)
    delta = maxdist - (scannerRad - clearance.distance)

    return :INVALID, 1.0001*delta * corners[maxidx,1] / maxdist, 1.0001*delta * corners[maxidx,2] / maxdist
  end
end

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