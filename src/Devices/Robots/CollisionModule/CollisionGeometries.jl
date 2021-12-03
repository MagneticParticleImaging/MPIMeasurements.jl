export Geometry, Circle, Rectangle, Triangle
export checkCollisionYZCircle
abstract type Geometry end
@mustimplement name(geometry::Geometry)

const geometryMinimum = 1.0Unitful.mm

struct Circle <: Geometry
  diameter::typeof(1.0Unitful.mm)
  name::String

  function Circle(;diameter::Unitful.Length, name::String)
    if diameter < geometryMinimum
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
    if width < geometryMinimum || height < geometryMinimum
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
    if width < geometryMinimum || height < geometryMinimum
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

"Returns true, 0mm, 0mm if given geometry does not collide with the scanner radius based on  given position and clearance"
@mustimplement checkCollisionYZCircle(geo::Geometry, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Unitful.Length)

function checkCollisionYZCircle(geo::Circle, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Unitful.Length)
  r = sqrt(posY^2 + posZ^2)

  if scannerRad - clearance >= r + geo.diameter / 2
    return true, zero(0.0u"mm"), zero(0.0u"mm")
  else
    delta_r = r - (scannerRad - clearance)
    delta_y1 = (delta_r+geo.diameter/2) * posY/r
    delta_z1 = (delta_r+geo.diameter/2) * posZ/r
    return false, 1.0001*delta_y1, 1.0001*delta_z1
  end 
end

function checkCollisionYZCircle(geo::Rectangle, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Unitful.Length)
  corners = [ [posY - geo.width / 2 posZ - geo.height / 2]
              [posY - geo.width / 2 posZ + geo.height / 2]
              [posY + geo.width / 2 posZ + geo.height / 2]
              [posY + geo.width / 2 posZ - geo.height / 2] ];

  dist = norm.(eachrow(corners))
  if all(dist .< (scannerRad - clearance))
    return true, zero(0.0u"mm"), zero(0.0u"mm")
  else
    maxdist, maxidx = findmax(dist)
    delta = maxdist - (scannerRad - clearance)
    if abs(posY) < geo.width/2 + 1u"mm"
      return false, 0.0u"mm", (corners[maxidx,2] - sign(corners[maxidx,2])*sqrt((scannerRad-clearance)^2-(1.0001*corners[maxidx,1])^2))
    end
    if abs(posZ) < geo.height/2 + 1u"mm"
      return false, (corners[maxidx,1] - sign(corners[maxidx,1])*sqrt((scannerRad-clearance)^2-(1.0001*corners[maxidx,2])^2)), 0.0u"mm"
    end

    return false, 1.0001*delta * corners[maxidx,1] / maxdist, 1.0001*delta * corners[maxidx,2] / maxdist
  end
end

function checkCollisionYZCircle(geo::Triangle, scannerRad::Unitful.Length, posY::Unitful.Length, posZ::Unitful.Length, clearance::Unitful.Length)
  # following code only for symmetric triangles / center of gravity = center of plug adapter

  corners = [ [posY   posZ + 2/3 * geo.height]
              [posY-geo.width/2   posZ - 1/3 * geo.height]
              [posY+geo.width/2   posZ - 1/3 * geo.height] ];

  dist = norm.(eachrow(corners))
  if all(dist .< (scannerRad - clearance))
    return true, zero(0.0u"mm"), zero(0.0u"mm")
  else
    maxdist, maxidx = findmax(dist)
    delta = maxdist - (scannerRad - clearance)

    return false, 1.0001*delta * corners[maxidx,1] / maxdist, 1.0001*delta * corners[maxidx,2] / maxdist
  end
end


