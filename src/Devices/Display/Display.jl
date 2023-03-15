export Display

abstract type Display <: Device end

Base.close(disp::Display) = nothing

export getDisplays
getDisplays(scanner::MPIScanner) = getDevices(scanner, Display)

export getDisplay
getDisplay(scanner::MPIScanner) = getDevice(scanner, Display)

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