export Clearance, AbstractCollisionModule, AbstractCollisionModule3D
export checkCoords, checkCoordTable

abstract type AbstractCollisionModule <: VirtualDevice end
abstract type AbstractCollisionModule3D <: AbstractCollisionModule end

# Robot Constants
const minClearance = 0.5Unitful.mm;

struct Clearance
  distance::typeof(1.0Unitful.mm)
  Clearance(distance) = distance < minClearance ? error("Clearance below minimum") : new(distance)
end

convert(::Type{Clearance}, x::Unitful.Length) = Clearance(x)

@mustimplement _checkCoordinate(cm::AbstractCollisionModule, pos::AbstractVector{<:Unitful.Length})

function init(cm::AbstractCollisionModule)
  @debug "Initializing CollisionModule with ID `$(cm.deviceID)`."
  cm.present = true
end

checkDependencies(cm::AbstractCollisionModule) = true

Base.close(cm::AbstractCollisionModule) = nothing


include("SimpleBoreCollisionModule.jl")

function checkCoords(cm::AbstractCollisionModule, pos::AbstractVector{<:Unitful.Length}; returnVerbose=false)
  result_status, result_dist = _checkCoordinate(cm, pos)
  if !returnVerbose
    return all(result_status .== :VALID)
  end
  return result_status, result_dist
end

"if the function is called on a vector of collision modules return the logic AND of all decisions"
checkCoords(cms::Vector{<:AbstractCollisionModule}, args...) = .&([checkCoords(cm, args...; returnVerbose=false) for cm in cms]...)

checkCoords(cm::AbstractCollisionModule, pos::RobotCoords; kwargs...) = error("The CollisionModule is defined on scanner coordinates! Please make sure you are using the correct coordinate system")
checkCoords(cm::AbstractCollisionModule, pos::ScannerCoords; kwargs...) = checkCoords(cm, pos.data; kwargs...)

checkCoords(cm::AbstractCollisionModule3D, positions::Positions) = [checkCoords(cm, pos; returnVerbose=false) for pos in positions]

"""Convenience function to check an array of nx3 position vectors at once"""
function checkCoords(cm::AbstractCollisionModule3D, positions::AbstractMatrix{<:Unitful.Length})
  numPos, dim = size(positions);

  if dim != 3
    error("Only 3-dimensional coordinates accepted!")
  end

  table = Array{Bool}(undef, numPos)
  for (i, pos) in enumerate(eachrow(positions))
    table[i] = checkCoords(cm, pos, returnVerbose=false)
  end
  return table
end

### Functions to check multiple cooridnates in a more verbose manner

checkCoordTable(cm::AbstractCollisionModule3D, positions::Positions; kwargs...) = checkCoordTable(cm, permutedims(hcat(collect(positions)...)); kwargs...)

function checkCoordTable(cm::AbstractCollisionModule3D, positions::AbstractMatrix{<:Unitful.Length}; plotresults=false)
  numPos, dim = size(positions);

  if dim != 3
    error("Only 3-dimensional coordinates accepted!")
  end

  table = Array{Any}(undef, numPos, 6)
  for (i, pos) in enumerate(eachrow(positions))
    tmp = checkCoords(cm, pos, returnVerbose=true)
    table[i,:] .= vcat(tmp...)
  end

  table = hcat(collect(1:numPos), positions, table)
  # table headlines
  headline = ["#" "x" "y" "z" "Status x" "Status y" "Status z" "delta_x" "delta_y" "delta_z"]
  # create final table
  coordTable = vcat(headline, table)
  
  errorIndices = unique(getindex.(findall(x -> x == :INVALID, table[:,5:7]), 1)) # get row index of all coordinates where at least one dimension in invalid
  
  if isempty(errorIndices)
    display("All coordinates are safe!");
  else
    display("Used geometry: $(cm.params.objGeometry.name)")
    display("Used scanner diameter: $(cm.params.scannerDiameter)")
    display("Following coordinates are dangerous and NOT valid!");
    @info errorIndices
    # ERROR: BoundsError
    errorTable = coordTable[[1,(errorIndices .+ 1)...], :];
    display(errorTable)
    
    plotresults ? plotSafetyErrors(cm, errorIndices, positions) : display("Plotting not chosen...")
  end
  return coordTable
end

