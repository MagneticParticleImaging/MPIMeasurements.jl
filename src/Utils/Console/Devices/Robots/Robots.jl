@devicecommand function enable(rob::Robot)
  enable(rob)
  println("The robot is now enabled.")
  return
end

@devicecommand function disable(rob::Robot)
  disable(rob)
  println("The robot is now disabled.")
  return
end

@devicecommand function reset(rob::Robot)
  disable(rob)
  println("The robot is now reeset.")
  return
end

@devicecommand function reference(rob::Robot)
  doReferenceDrive(rob)
  println("The robot is now referenced.")
  return
end

@devicecommand function referenced(rob::Robot)
  if isReferenced(rob)
    println("The robot is currently referenced.")
  else
    println("The robot is currently not referenced.")
  end

  return
end

@devicecommand function move(rob::Robot, type::String, position::Vector{<:Unitful.Length})
  if type == "rel" || type == "relative"
    moveRel(rob, position)
  elseif type == "abs" || type == "absolute"
    moveAbs(rob, position)
  else
    println("The movement type `$type` could not be recognized. Please use either `abs` or `rel`.")
  end

  return
end

@devicecommand function position(rob::Robot)
  if !isnothing(getPosition(rob))
    println("The current position is $(string.(getPosition(rob))).")
  else
    println("The current position is not defined.")
  end

  return
end