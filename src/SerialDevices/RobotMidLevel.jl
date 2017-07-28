using Graphics: @mustimplement

export BrukerScanner, HeadScanner, Scanner
export name,device,robotSetup,onlineRecoLoop
export scannerSymbols

const scannerSymbols = [:BrukerScanner, :BrukerEmulator, :HeadScanner, :HeadEmulator]

@compat abstract type Scanner end

@mustimplement name(scanner::Scanner)
@mustimplement device(scanner::Scanner)
@mustimplement robotSetup(scanner::Scanner)
@mustimplement onlineRecoLoop(scanner::Scanner)

@compat struct BrukerScanner{T<:Device} <: Scanner
  name::Symbol
  device::ServerDevice{T}
  robotSetup::RobotSetup
  onlineRecoLoop::Function
  BrukerScanner{T}(name::Symbol,device::ServerDevice{T},robotSetup::RobotSetup) where T<:Device = new{T}(name,device,robotSetup,()->())
  BrukerScanner{T}(name::Symbol,device::ServerDevice{T},robotSetup::RobotSetup, onlineRecoLoop::Function) where T<:Device = new{T}(name,device,robotSetup,onlineRecoLoop)
end

name(scanner::BrukerScanner) = scanner.name
device(scanner::BrukerScanner) = scanner.device
robotSetup(scanner::BrukerScanner) = scanner.robotSetup
onlineRecoLoop(scanner::BrukerScanner) = scanner.onlineRecoLoop

@compat struct HeadScanner{T<:Device} <: Scanner
  name::Symbol
  device::SerialDevice{T}
  robotSetup::RobotSetup
  onlineRecoLoop::Function
  HeadScanner{T}(name::Symbol,device::SerialDevice{T},robotSetup::RobotSetup) where T<:Device = new{T}(name,device,robotSetup,()->())
  HeadScanner{T}(name::Symbol,device::SerialDevice{T},robotSetup::RobotSetup,onlineRecoLoop::Function) where T<:Device = new{T}(name,device,robotSetup,onlineRecoLoop)
end

name(scanner::HeadScanner) = scanner.name
device(scanner::HeadScanner) = scanner.device
robotSetup(scanner::HeadScanner) = scanner.robotSetup
onlineRecoLoop(scanner::HeadScanner) = scanner.onlineRecoLoop

""" `moveCenter(scanner::Scanner)` """
function moveCenter(scanner::Scanner)
  d = device(scanner)
  moveCenter(d)
end

""" `movePark(scanner::Scanner)` """
function movePark(scanner::Scanner)
  d = device(scanner)
  movePark(d)
end

""" `moveAbs(scanner::Scanner, xyzPos::Vector{typeof(1.0u"mm")})` Robot MidLevel """
function moveAbs(scanner::Scanner, xyzPos::Vector{typeof(1.0u"mm")})
  if length(xyzPos)!=3
    error("position vector xyzDist needs to have length = 3, but has length: ",length(xyzDist))
  end
  rSetup = robotSetup(scanner)
  coordsTable = checkCoords(rSetup, xyzPos)
  d = device(scanner)
  moveAbs(d,xyzPos[1],xyzPos[2],xyzPos[3])
end

""" Not Implemented """
function moveRel(scanner::Scanner, xyzDist::Vector)
  error("Not implemented")
end
