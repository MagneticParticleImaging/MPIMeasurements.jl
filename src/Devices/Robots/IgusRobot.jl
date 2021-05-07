export IgusRobot, IgusRobotParams

using Sockets
const SDOObj = @NamedTuple{addr::UInt16, subidx::UInt8, bytes::UInt8}

# available objects defined in D1 (motor controller) handbook section 6.4.13
const CONTROLWORD = SDOObj((0x6040, 0, 2))
const STATUSWORD = SDOObj((0x6041, 0, 2))
const MODES_OF_OPERATION = SDOObj((0x6060, 0, 1))
const POSITION_ACTUAL_VALUE = SDOObj((0x6064, 0, 4))
const VELOCITY_ACTUAL_VALUE = SDOObj((0x606C, 0, 4))
const TARGET_POSITION = SDOObj((0x607A, 0, 4)) 
const PROFILE_VELOCITY = SDOObj((0x6081, 0, 4))
const PROFILE_ACCELERATION = SDOObj((0x6083, 0, 4)) 
const PROFILE_DECELERATION = SDOObj((0x6084, 0, 4))
const FEED_CONSTANT_FEED = SDOObj((0x6092, 1, 4))
const FEED_CONSTANT_SHAFT_REV = SDOObj((0x6092, 2, 4))
const HOMING_SPEED_DURING_SEARCH_FOR_SWITCH = SDOObj((0x6099, 1, 4))
const HOMING_SPEED_DURING_SEARCH_FOR_ZERO = SDOObj((0x6099, 2, 4))
const HOMING_ACCELERATION = SDOObj((0x609A, 0, 4))
const DIGITAL_INPUTS = SDOObj((0x60fd, 0, 4))
const DIGITAL_OUTPUTS = SDOObj((0x60fe, 1, 4))

# important bit patterns for the CONTROLWORD
const COMMANDS = Dict(
"READY_TO_SWITCH_ON" => 0b0000_0000_0000_0110,
"SWITCH_ON" => 0b0000_0000_0000_0111, 
"ENABLE_OPERATION" => 0b0000_0000_0000_1111, 
"START_OPERATION" => 0b0000_0000_0001_1111)

const MODES = Dict(
"PROFILE_POSITION" => 1,
"HOMING" => 6)

Base.@kwdef struct IgusRobotParams <: DeviceParams
    defaultVelocity::Vector{typeof(1.0u"mm/s")} = [10.0u"mm/s"]
    axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[0,500.0]]u"mm"
    ip::IPv4 = ip"192.168.1.3"
    port::Int = 1111
    keepSocketOpen::Bool = true
    stepsPermm::Int = 100
    feed::typeof(1.0u"mm") = 2.0u"mm"
    shaftRev::Int = 1
    homVelSwitch::typeof(1.0u"mm/s") = 10.0u"mm/s"
    homVelZero::typeof(1.0u"mm/s") = 2u"mm/s"
    homAcc::typeof(1.0u"mm/s^2") = 100.0u"mm/s^2"
    movAcc::typeof(1.0u"mm/s^2") = 100.0u"mm/s^2"
    movDec::typeof(1.0u"mm/s^2") = 100.0u"mm/s^2"
    timeout::typeof(1.0u"s") = 10u"s"
end

mutable struct IgusRobot <: Robot
    deviceID::String
    params::IgusRobotParams
    state::RobotState
    socket::Union{TCPSocket,Nothing}
    function IgusRobot(deviceID::String, params::IgusRobotParams)
        return new(deviceID, params, INIT, nothing)
    end
end

state(rob::IgusRobot) = rob.state
setstate!(rob::IgusRobot, state::RobotState) = rob.state=state

dof(rob::IgusRobot) = 1
getPosition(rob::IgusRobot) = try [getSdoObject(rob, POSITION_ACTUAL_VALUE) / rob.params.stepsPermm * u"mm"] catch; return [NaN]u"mm" end
axisRange(rob::IgusRobot) = rob.params.axisRange
isReferenced(rob::IgusRobot) = (getSdoObject(rob, DIGITAL_OUTPUTS) & (1 << 26))!=0
defaultVelocity(rob::IgusRobot) = rob.params.defaultVelocity

function _moveAbs(rob::IgusRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    if speed === nothing
        speed = defaultVelocity(rob)
    end
    
    setSdoObject(rob, TARGET_POSITION, round(Int, ustrip(u"mm", pos[1]) * rob.params.stepsPermm))
	setSdoObject(rob, PROFILE_VELOCITY, round(Int, ustrip(u"mm/s", speed[1]) * rob.params.stepsPermm))
    dist = abs.(getPosition(rob)-pos)
    setSdoObject(rob, CONTROLWORD, COMMANDS["ENABLE_OPERATION"])
	sleep(0.2)
	setSdoObject(rob, CONTROLWORD, COMMANDS["START_OPERATION"])

	waittime = 0.0u"s"
	while (getSdoObject(rob, STATUSWORD) & 1 << 10) == 0  # Bis das Bit Target Reached nicht gesetzt ist, warte noch ein bisschen
		sleep(0.05)
        waittime += 0.05u"s"
		if (waittime > dist[1] / speed[1] + rob.params.timeout) 
			@error "Timeout: Movement not completed in expected time"
            rob.state = :ERROR
            return
        end
    end
    @debug "Finished movement at x=$(getPosition(rob)[1])"
end

function _moveRel(rob::IgusRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

    if speed === nothing
        speed = defaultVelocity(rob)
    end
	setSdoObject(rob, TARGET_POSITION, round(Int, ustrip(u"mm", dist[1]) * rob.params.stepsPermm))
	setSdoObject(rob, PROFILE_VELOCITY, round(Int, ustrip(u"mm/s", speed[1]) * rob.params.stepsPermm))
    
    setSdoObject(rob, CONTROLWORD, COMMANDS["ENABLE_OPERATION"] | 1 << 6)
	sleep(0.2)
	setSdoObject(rob, CONTROLWORD, COMMANDS["START_OPERATION"] | 1 << 6)

	waittime = 0.0u"s"
	while (getSdoObject(rob, STATUSWORD) & 1 << 10) == 0  # Bis das Bit Target Reached nicht gesetzt ist, warte noch ein bisschen
		sleep(0.05)
        waittime += 0.05u"s"
		if (waittime > dist[1] / speed[1] + rob.params.timeout) 
			@error "Timeout: Movement not completed in expected time"
            rob.state = :ERROR
            return
        end
    end
    @debug "Finished relative movement"
end

function _enable(rob::IgusRobot)
    if (getSdoObject(rob, DIGITAL_INPUTS) & (1 << 22)) == 0
        error("Enable ist nicht gesetzt, bitte D7 im Webinterface aktivieren")
    end
    

    setSdoObject(rob, CONTROLWORD, COMMANDS["SWITCH_ON"])
    @debug "Set switch on"
    sleep(0.2)
    setSdoObject(rob, CONTROLWORD, COMMANDS["ENABLE_OPERATION"])
    @debug "Set enable operation"
end

function _disable(rob::IgusRobot)
    setSdoObject(rob, CONTROLWORD, COMMANDS["READY_TO_SWITCH_ON"]) # Disable Operation
end

function _reset(rob::IgusRobot)
    println("TODO: implement proper reset")
    try
        disable(rob)
        close(rob.socket)
    catch e
        @error "During reset of the robot the following excpetion was thrown: $e"
    end
end

function _setup(rob::IgusRobot)
    # Setzt alle relevanten, nur einmalig zu setzenden Parameter.
	# Eventuell werden diese in der Steuerung auch beim nächsten Boot gespeichert, vielleicht aber auch nicht
    
	# Feed_constant_Feed Angabe des Vorschubs
	setSdoObject(rob, FEED_CONSTANT_FEED, round(Int, ustrip(u"mm", rob.params.feed) * rob.params.stepsPermm))

	# Feed_constant_Shaft_revolutions Angabe des Achswellenumdrehungen
	setSdoObject(rob, FEED_CONSTANT_SHAFT_REV, rob.params.shaftRev)

	# Normale Bewegung
	# Profile_acceleration
	setSdoObject(rob, PROFILE_ACCELERATION, round(Int, ustrip(u"mm/s^2", rob.params.movAcc) * rob.params.stepsPermm))

	# Profile_deceleration
	setSdoObject(rob, PROFILE_DECELERATION, round(Int, ustrip(u"mm/s^2", rob.params.movDec) * rob.params.stepsPermm))

	setSdoObject(rob, MODES_OF_OPERATION, 1) # Mode of Operation -> Profile Position Mode

	sleep(0.1)

    setSdoObject(rob, CONTROLWORD, COMMANDS["READY_TO_SWITCH_ON"]) # Disable Operation
	@debug "Initialisierung abgeschlossen"
end

function _doReferenceDrive(rob::IgusRobot)
    # Die Homing Methode 0x6098 muss über die Webserver Benutzeroberfläche eingestellt werden
	# Ebenso der Homing Offset

    # Vorgabe der Verfahrgeschwindigkeiten während der Referenzfahrt
    @debug "Setting reference speed"
	setSdoObject(rob, HOMING_SPEED_DURING_SEARCH_FOR_SWITCH, round(Int, ustrip(u"mm/s", rob.params.homVelSwitch) * rob.params.stepsPermm))
	setSdoObject(rob, HOMING_SPEED_DURING_SEARCH_FOR_ZERO, round(Int, ustrip(u"mm/s", rob.params.homVelZero) * rob.params.stepsPermm))
	setSdoObject(rob, HOMING_ACCELERATION, round(Int, ustrip(u"mm/s^2", rob.params.homAcc) * rob.params.stepsPermm))

    @debug "Calibrating Igus table"
    setSdoObject(rob, MODES_OF_OPERATION, MODES["HOMING"])  
    
    sleep(0.2) # wait for the mode to be activated

    @debug "Performing reference drive"
    setSdoObject(rob, CONTROLWORD, COMMANDS["START_OPERATION"])
    sleep(0.2)
    waittime = 0.2u"s"
    while (getSdoObject(rob, STATUSWORD) & 0x1400) == 0
        sleep(0.1)
        waittime += 0.1u"s"
        if waittime > abs(diff(axisRange(rob)[1])[1]) / rob.params.homVelSwitch + rob.params.timeout
            sleep(0.05)
            @error "Timeout: Reference drive not completed in expected time!"
            rob.state = :ERROR
            return false
        end
    end

    setSdoObject(rob, MODES_OF_OPERATION, MODES["PROFILE_POSITION"])
    return true
end


"""
    createModbusTelegram(sdoObject::SDOObj)
Creates a TCP payload that will be identified as a read-only modbus command by the motor controller
"""
function createModbusTelegram(sdoObject::SDOObj)

    telegram = zeros(UInt8, 19)

    telegram[1] = rand(UInt8)
    telegram[6] = 13  # number of bytes to be expected after this byte
    telegram[8] = 0x2b  # indicates Modbus TCP packet
    telegram[9] = 0x0d  # indicates Modbus TCP packet

    telegram[13] = sdoObject.addr >> 8
    telegram[14] = sdoObject.addr & 0xff
    telegram[15] = sdoObject.subidx
    telegram[19] = sdoObject.bytes


    return telegram
end

"""
    createModbusTelegram(sdoObject::SDOObj, data::Integer)
Creates a TCP payload that will write `data` into the given `sdoObject`
"""
function createModbusTelegram(sdoObject::SDOObj, data::Integer)

    
    telegram = createModbusTelegram(sdoObject)
    payloadBytes = telegram[19]

    telegram[6] += payloadBytes # add number of bytes to write to total length
    telegram[10] = 1 # write data
    
    
    for i in 1:payloadBytes
        push!(telegram, data & 0xff)
        data >>= 8
    end
    
    return telegram
end

"""
    readModbusTelegram(telegram::Vector{UInt8})
Checks the received telegram for error codes and returns the data payload
"""
function readModbusTelegram(telegram::Vector{UInt8})

    if telegram[7] == 0xab
        errCode = telegram[9]
		if errCode == 1
			@error "Fehler im Antwort-Telegram: Ungültiger Funktions-Code" # Sollte nicht auftreten, ist in createModbusTelegram hart eincodiert
        elseif errCode == 2
			@error "Fehler im Antwort-Telegram: Ungültige Daten-Adresse"
		elseif errCode == 3
			@error "Fehler im Antwort-Telegram: Ungültiger Daten-Wert"
        elseif errCode == 4
			@error "Fehler im Antwort-Telegram: Geräte Fehler"
        elseif errCode == 5
            @error "Fehler im Antwort-Telegram: Bestätigung. (Verarbeitung dauert noch, Nachricht aber erhalten)"
		elseif errCode == 6
			@error "Fehler im Antwort-Telegram: Server ausgelastet"
        else
			@error "Unbekannter Fehler im Antworttelegramm"
        end
        return nothing

    else
        objectSize = telegram[19]

        data = 0

     # convert bytes to int (little endian)
        for i in 1:objectSize
            data += telegram[19 + i] * 256^(i - 1)
            @debug "Reading telegram" telegram[19 + i]
        end
        
        return data
    end

end

"""
    getSdoObject(rob::IgusRobot, sdoObject::SDOObj)
Queries the `rob` and returns the value of the chosen `sdoObject`
"""
function getSdoObject(rob::IgusRobot, sdoObject::SDOObj)

    telegram = createModbusTelegram(sdoObject)

    recvTelegram = sendAndReceiveTelegram(rob, telegram)
    data = readModbusTelegram(recvTelegram)
    if data === nothing
        rob.state = :ERROR
        return nothing
    end
    return data

end

"""
    setSdoObject(rob::IgusRobot, sdoObject::SDOObj, value::Integer)
Queries the `rob` and sets a new `value` for the chosen `sdoObject`
"""
function setSdoObject(rob::IgusRobot, sdoObject::SDOObj, value::Integer)

    telegram = createModbusTelegram(sdoObject, value)
    rsp = sendAndReceiveTelegram(rob, telegram)
    if readModbusTelegram(rsp) === nothing
        rob.state = :ERROR
        return false
    end
    return true    

    
end

"""
    sendAndReceiveTelegram(rob::IgusRobot, telegram::Vector{UInt8})
"""
function sendAndReceiveTelegram(rob::IgusRobot, telegram::Vector{UInt8})

    try 
        if rob.socket === nothing || !isopen(rob.socket)
            @debug "Opening socket"
            rob.socket = connect(rob.params.ip, rob.params.port)
        end

    # the base length is always 19, if the telegram is a read request the length of the object will be added to the response
        answerBytes = 19 + (1 - telegram[10]) * telegram[19] 

        write(rob.socket, telegram)

        rsp = read(rob.socket, answerBytes)

        if telegram[1] != rsp[1]
            @error "Die erhaltene Antwort stimmt nicht mit der ID der Anfrage überein. Dies passiert eigentlich nur, wenn man auch etwas falsches/unerwartetes geschickt hat und die Steuerung überfordert ist... Der Socket wird geschlossen und die Verbindung bei der nächsten Anfrage neu aufgebaut"
            rob.state = :ERROR
            close(rob.socket)
            rob.socket = nothing
        elseif !rob.params.keepSocketOpen
            @debug "Closing socket"
            close(rob.socket)
            rob.socket = nothing
        end

        return rsp

    catch e
        @error "The communication to IgusRobot failed with error $e"
        rob.state = :ERROR
        return nothing
    end
end