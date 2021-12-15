using Graphics: @mustimplement

export Display

abstract type Display <: Device end

Base.close(disp::Display) = nothing

@mustimplement direction(disp::Display)
@mustimplement direction(disp::Display, dir::DisplayDirection)


getDisplays(scanner::MPIScanner) = getDevices(scanner, Display)
function getDisplay(scanner::MPIScanner)
  displays = getDisplays(scanner)
  if length(Displays) > 1
    error("The scanner has more than one display device. Therefore, a single display cannot be retrieved unambiguously.")
  else
    return displays[1]
  end
end



include("SimulatedDisplay.jl")