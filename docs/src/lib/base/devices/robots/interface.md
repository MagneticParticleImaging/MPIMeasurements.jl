# Robots

## Interface


## Must Implement

```@docs
MPIMeasurements.dof(::Robot)
MPIMeasurements.axisRange(::Robot)
MPIMeasurements.defaultVelocity(::Robot)
MPIMeasurements._moveAbs(::Robot, ::Vector{<:Unitful.Length}, ::Union{Vector{<:Unitful.Velocity},Nothing})
MPIMeasurements._moveRel(::Robot, ::Vector{<:Unitful.Length}, ::Union{Vector{<:Unitful.Velocity},Nothing})
MPIMeasurements._enable(::Robot)
MPIMeasurements._disable(::Robot)
MPIMeasurements._reset(::Robot)
MPIMeasurements._doReferenceDrive(::Robot)
MPIMeasurements._isReferenced(::Robot)
MPIMeasurements._getPosition(::Robot)
```