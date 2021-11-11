export ScannerCoordinateSystem, toScannerCoords
abstract type DeviceCoords{T<:Unitful.Length} <: AbstractVector{T} end

struct ScannerCoords{T<:Unitful.Length} <: AbstractVector{T}
  data::Vector{T}
end

struct ScannerCoordinateSystem
  """Matrix defining the axes of the scanner coordinate system, the first column is the scanner x axis in robot coordinates"""
  axes::Matrix{Float64}
  """The origin should be set, so that the objGeometry is centered in the crosssection of the bore, the zero of the bore axis is not important, as the available boreAxis range is set by minMaxBoreAxis"""
  origin::Vector{typeof(1.0u"mm")}
  function ScannerCoordinateSystem(dof::Integer)
    return new(Matrix(1.0LinearAlgebra.I, dof, dof), zeros(dof)*u"mm")
  end
  function ScannerCoordinateSystem(axes::Matrix{<:Real}, origin::Vector{<:Unitful.Length})
    dim = length(origin)
    @assert all(isequal(dim), size(axes))
    return new(axes, origin)
  end
end

Base.Broadcast.broadcastable(val::ScannerCoordinateSystem) = Ref(val) # Otherwise tryuparse.(val) returns [val]

ScannerCoordinateSystem(axes::Matrix{<:Real}, origin::Nothing) = ScannerCoordinateSystem(axes, zeros(size(axes, 1))*u"mm")
ScannerCoordinateSystem(axes::Nothing, origin::Vector{<:Unitful.Length}) = ScannerCoordinateSystem(Matrix(1.0LinearAlgebra.I, length(origin), length(origin)), origin)
function ScannerCoordinateSystem(axes::AbstractString, origin)
  axes_split = split(lowercase(axes),",")
  cs_matrix = zeros(length(axes_split),length(axes_split))
  for (i,ax) in enumerate(axes_split)
    cs_matrix[i,ax[end]-'w'] = (ax[1]=='-' ? -1. : 1.)
  end
  return ScannerCoordinateSystem(cs_matrix, origin)
end
ScannerCoordinateSystem(axes::AbstractVector{<:AbstractVector{<:Real}}, origin) = ScannerCoordinateSystem(Matrix{Float64}(hcat(axes...)), origin)

function toScannerCoords(sys::ScannerCoordinateSystem, coords::DeviceCoords)
  shifted = coords.data - sys.origin
  return ScannerCoords(sys.axes * shifted)
end
toScannerCoords(sys::ScannerCoordinateSystem, coords::ScannerCoords) = coords

function toDeviceCoords(sys::ScannerCoordinateSystem, coords::ScannerCoords, T::Type{<:DeviceCoords})
  rotated = inv(sys.axes) * coords.data
  return T(rotated + sys.origin)
end