using Unitful, HDF5

import Base: getindex, length, convert, start, done, next, write

export AbstractPosition, ParkPosition, CenterPosition
export Positions, CartesianGridPositions, ChebyshevGridPositions, MeanderingGridPositions, UniformRandomPositions, ArbitraryPositions, ShpericalTDesign
export loadTDesign

@compat abstract type AbstractPosition end
@compat struct ParkPosition <: AbstractPosition end
@compat struct CenterPosition <: AbstractPosition end


@compat abstract type Positions end
@compat abstract type GridPositions<:Positions end

function Positions(file::HDF5File)

  typ = h5read(file, "/positionsType")
  if typ == "CartesianGrid"
    positions = CartesianGridPositions(file)
  else
    error("Implement all the other grids!!!")
  end

  if exists(file, "/positionsMeandering") &&
      h5read(file, "/positionsMeandering") == Int8(1)
    positions = MeanderingGridPositions(positions)
  end
  return positions
end

# Cartesian grid
type CartesianGridPositions{S,T} <: GridPositions where {S,T<:Unitful.Length}
  shape::Vector{Int}
  fov::Vector{S}
  center::Vector{T}
end

function CartesianGridPositions(file::HDF5File)
  shape = h5read(file, "/positionsShape")
  fov = h5read(file, "/positionsFov")*u"m"
  center = h5read(file, "/positionsCenter")*u"m"
  return CartesianGridPositions(shape,fov,center)
end

function write(file::HDF5File, positions::CartesianGridPositions)
  write(file,"/positionsType", "CartesianGrid")
  write(file, "/positionsShape", positions.shape)
  write(file, "/positionsFov", ustrip(uconvert.(u"m", positions.fov)) )
  write(file, "/positionsCenter", ustrip(uconvert.(u"m", positions.center)) )
end

function getindex(grid::CartesianGridPositions, i::Integer)
  if i>length(grid) || i<1
    throw(BoundsError)
  else
    idx = collect(ind2sub(tuple(shape(grid)...), i))
    return ((-shape(grid).+(2.*idx.-1))./shape(grid)).*fieldOfView(grid)./2 + fieldOfViewCenter(grid)
  end
end

# Chebyshev Grid
type ChebyshevGridPositions{S,T} <: GridPositions where {S,T<:Unitful.Length}
  shape::Vector{Int}
  fov::Vector{S}
  center::Vector{T}
end

function getindex(grid::ChebyshevGridPositions, i::Integer)
  if i>length(grid) || i<1
    throw(BoundsError)
  else
    idx = collect(ind2sub(tuple(shape(grid)...), i))
    return -cos.((idx.-0.5).*pi./shape(grid)).*fieldOfView(grid)./2 .+ fieldOfViewCenter(grid)
  end
end

# Meander regular grid positions
type MeanderingGridPositions <: GridPositions
  grid::GridPositions
end

function write(file::HDF5File, positions::MeanderingGridPositions)
  write(file,"/positionsMeandering", Int8(1))
  write(file, positions.grid )
end

function getindex(grid::MeanderingGridPositions, i::Integer)
  dims = tuple(shape(grid)...)
  idx = collect(ind2sub(dims, i))
  for d=2:3
    if isodd(sum(idx[d:3])-length(idx[d:3]))
      idx[d-1] = shape(grid)[d-1] + 1 - idx[d-1]
    end
  end
  linidx = sub2ind(dims,idx...)
  return grid.grid[linidx]
end

function getPermutation(grid::MeanderingGridPositions)
  N = tuple(shape(grid)...)

  perm = Array{Int}(N)
  for i in CartesianRange(N)
    idx = [i[k] for k=1:length(i)]
    for d=2:3
      if isodd(sum(idx[d:3])-length(idx[d:3]))
        idx[d-1] = N[d-1] + 1 - idx[d-1]
      end
    end
    perm[i] = sub2ind(N,idx...)
  end
  return vec(perm)
end

#TODO Meander + BG
# capsulate objects of type GridPositions and return to ParkPosition every so often

# Uniform random distributed positions
type UniformRandomPositions{S,T} <: Positions where {S,T<:Unitful.Length}
  N::UInt
  seed::UInt32
  fov::Vector{S}
  center::Vector{T}
end

seed(rpos::UniformRandomPositions) = rpos.seed

function getindex(rpos::UniformRandomPositions, i::Integer)
  if i>length(rpos) || i<1
    throw(BoundsError)
  else
    # make sure Positions are randomly generated from given seed
    mersenneTwister = MersenneTwister(seed(rpos))
    rP = rand(mersenneTwister, 3, i)[:,i]
    return (rP.-0.5).*fieldOfView(rpos)+fieldOfViewCenter(rpos)
  end
end

# TODO fix conversion methods
function convert(::Type{UniformRandomPositions}, N::Integer,seed::UInt32,fov::Vector{S},center::Vector{T}) where {S,T<:Unitful.Length}
  if N<1
    throw(DomainError)
  else
    uN = convert(UInt,N)
    return UniformRandomPositions(uN,seed,fov,center)
  end
end

function convert(::Type{UniformRandomPositions}, N::Integer,fov::Vector,center::Vector)
  return UniformRandomPositions(N,rand(UInt32),fov,center)
end


# General functions for handling grids
fieldOfView(grid::GridPositions) = grid.fov
fieldOfView(grid::UniformRandomPositions) = grid.fov
fieldOfView(mgrid::MeanderingGridPositions) = fieldOfView(mgrid.grid)
shape(grid::GridPositions) = grid.shape
shape(mgrid::MeanderingGridPositions) = shape(mgrid.grid)
fieldOfViewCenter(grid::GridPositions) = grid.center
fieldOfViewCenter(grid::UniformRandomPositions) = grid.center
fieldOfViewCenter(mgrid::MeanderingGridPositions) = fieldOfViewCenter(mgrid.grid)


type ShpericalTDesign{S} <: Positions where {S<:Unitful.Length}
  T::Unsigned
  radius::S
  positions::Matrix
end

getindex(tdes::ShpericalTDesign, i::Integer) = tdes.radius.*tdes.positions[:,i]

"""
Returns the t-Design Array for choosen t and N.
"""
function loadTDesign(t::Int64, N::Int64, radius::S=10u"mm", filename::String=joinpath(Pkg.dir("MPIMeasurements"),"src/Robots/TDesigns.hd5")) where {S<:Unitful.Length}
  h5file = h5open(filename, "r")
  address = "/$t-Design/$N"

  if exists(h5file, address)
    positions = read(h5file, address)'
    return ShpericalTDesign(UInt(t),radius,positions)
  else
    if exists(h5file, "/$t-Design/")
      println("spherical $t-Design with $N Points does not exist!")
      println("There are spherical $t-Designs with following N:")
      Ns = Int[]
      for N in keys(read(h5file, string("/$t-Design")))
	push!(Ns,parse(Int,N))
      end
      sort!(Ns)
      println(Ns)
      throw(DomainError)
    else
      println("spherical $t-Design does not exist!")
      ts = Int[]
      for d in keys(read(h5file))
	m = match(r"(\d{1,})-(Design)",d)
	if m != nothing
	  push!(ts,parse(Int,m[1]))
        end
      end
      sort!(ts)
      println(ts)
      throw(DomainError)
    end
  end
end

# Unstructured collection of positions
type ArbitraryPositions{T} <: Positions where {T<:Unitful.Length}
  positions::Matrix{T}
end

getindex(apos::ArbitraryPositions, i::Integer) = apos.positions[:,i]

function convert(::Type{ArbitraryPositions}, grid::GridPositions)
  T = eltype(grid.fov)
  positions = zeros(T,3,length(grid))
  for i=1:length(grid)
    positions[:,i] = grid[i]
  end
  return ArbitraryPositions(positions)
end


# fuction related to looping
length(tdes::ShpericalTDesign) = size(tdes.positions,2)
length(apos::ArbitraryPositions) = size(apos.positions,2)
length(grid::GridPositions) = prod(grid.shape)
length(rpos::UniformRandomPositions) = rpos.N
length(mgrid::MeanderingGridPositions) = length(mgrid.grid)
start(grid::Positions) = 1
next(grid::Positions,state) = (grid[state],state+1)
done(grid::Positions,state) = state > length(grid)
