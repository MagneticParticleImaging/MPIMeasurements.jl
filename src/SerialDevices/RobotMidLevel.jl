using Graphics: @mustimplement

export Scanner, Scanner, BaseScanner
export name,device,robotSetup,onlineRecoLoop
export scannerSymbols

const scannerSymbols = [:BrukerScanner, :BrukerEmulator, :HeadScanner, :HeadEmulator]

@compat abstract type BaseScanner end

@mustimplement name(scanner::BaseScanner)
@mustimplement device(scanner::BaseScanner)
@mustimplement robotSetup(scanner::BaseScanner)
@mustimplement onlineRecoLoop(scanner::BaseScanner)

@compat struct Scanner{T<:Device} <: BaseScanner
  name::Symbol
  device::Union{ServerDevice{T},SerialDevice{T}}
  robotSetup::RobotSetup
  onlineRecoLoop::Function
  Scanner{T}(name::Symbol,device::ServerDevice{T},robotSetup::RobotSetup) where T<:Device = new{T}(name,device,robotSetup,()->())
  Scanner{T}(name::Symbol,device::ServerDevice{T},robotSetup::RobotSetup, onlineRecoLoop::Function) where T<:Device = new{T}(name,device,robotSetup,onlineRecoLoop)
end

name(scanner::Scanner) = scanner.name
device(scanner::Scanner) = scanner.device
robotSetup(scanner::Scanner) = scanner.robotSetup
onlineRecoLoop(scanner::Scanner) = scanner.onlineRecoLoop

# @compat struct Scanner{T<:Device} <: BaseScanner
#   name::Symbol
#   device::SerialDevice{T}
#   robotSetup::RobotSetup
#   onlineRecoLoop::Function
#   Scanner{T}(name::Symbol,device::SerialDevice{T},robotSetup::RobotSetup) where T<:Device = new{T}(name,device,robotSetup,()->())
#   Scanner{T}(name::Symbol,device::SerialDevice{T},robotSetup::RobotSetup,onlineRecoLoop::Function) where T<:Device = new{T}(name,device,robotSetup,onlineRecoLoop)
# end
#
# name(scanner::Scanner) = scanner.name
# device(scanner::Scanner) = scanner.device
# robotSetup(scanner::Scanner) = scanner.robotSetup
# onlineRecoLoop(scanner::Scanner) = scanner.onlineRecoLoop

""" `moveCenter(scanner::BaseScanner)` """
function moveCenter(scanner::BaseScanner)
  d = device(scanner)
  moveCenter(d)
end

""" `movePark(scanner::BaseScanner)` """
function movePark(scanner::BaseScanner)
  d = device(scanner)
  movePark(d)
end

""" `moveAbs(scanner::BaseScanner, xyzPos::Vector{typeof(1.0u"mm")})` Robot MidLevel """
function moveAbs(scanner::BaseScanner, xyzPos::Vector{typeof(1.0u"mm")})
  if length(xyzPos)!=3
    error("position vector xyzDist needs to have length = 3, but has length: ",length(xyzDist))
  end
  rSetup = robotSetup(scanner)
  coordsTable = checkCoords(rSetup, xyzPos)
  d = device(scanner)
  moveAbs(d,xyzPos[1],xyzPos[2],xyzPos[3])
end

""" Not Implemented """
function moveRel(scanner::BaseScanner, xyzDist::Vector)
  error("Not implemented")
end
