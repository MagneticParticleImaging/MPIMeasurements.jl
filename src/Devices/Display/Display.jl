using Graphics: @mustimplement

export Display

abstract type Display <: Device end

Base.close(disp::Display) = nothing

getDisplays(scanner::MPIScanner) = getDevices(scanner, Display)
function getDisplay(scanner::MPIScanner)
  displays = getDisplays(scanner)
  if length(Displays) > 1
    error("The scanner has more than one display device. Therefore, a single display cannot be retrieved unambiguously.")
  else
    return displays[1]
  end
end

export clear
@mustimplement clear(disp::Display)

export writeLine
@mustimplement writeLine(disp::Display, row::Integer, column::Integer, message::String)

export hasBacklight
hasBacklight(disp::Display) = false # Default

export setBacklight
@mustimplement setBacklight(disp::Display, state::Bool)

export backlightOn
backlightOn(disp::Display) = setBacklight(disp, true)

export backlightOff
backlightOff(disp::Display) = setBacklight(disp, false)

include("SimulatedDisplay.jl")
include("TinkerforgeBrickletLCD20x4Display.jl")
include("TinkerforgeBrickletOLED128x64V2.jl")