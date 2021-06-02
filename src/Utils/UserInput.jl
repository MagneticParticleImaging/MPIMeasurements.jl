# export getUserInput

# function getUserInput(T::DataType=String, msg::AbstractString="")
#   print("$msg ")
#   if T <: AbstractString
#       return chomp(readline())
#   else
#     try
#       value = parse(T, readline())
#       print("\n")
#       return value
#     catch
#       println("Could not interpret answer. Please try again")
#       return getUserInput(T, msg)
#     end
#   end
  
# end
# getUserInput(msg::AbstractString) = getUserInput(String, msg)

export getUserDecision

function getUserDecision(msg::AbstractString="")
  return ask_dialog(msg, "No", "Yes")
end