export SerialSCPIInstrument

mutable struct SerialSCPIInstrument <: SCPIInstrument
    serial_port::SerialPort
    is_connected::Bool
    delimiter::String

    function SerialSCPIInstrument(port::String,
        baudrate::Integer;
        mode::SPMode=SP_MODE_READ_WRITE,
        ndatabits::Integer=8,
        parity::SPParity=SP_PARITY_NONE,
        nstopbits::Integer=1,
        flow_control::Bool=false)
        inst =  new(open(port, baudrate, mode=mode), true, "\n")

        set_frame(inst.serial_port, ndatabits=ndatabits, parity=parity, nstopbits=nstopbits)

        if flow_control
            set_flow_control(inst.serial_port, rts= SP_RTS_FLOW_CONTROL, cts=SP_CTS_FLOW_CONTROL)
        else
            set_flow_control(inst.serial_port, rts= SP_RTS_OFF, cts=SP_CTS_IGNORE)
        end

        return inst
    end
end

function Base.close(inst::SerialSCPIInstrument)
    close(inst.serial_port)
    inst.is_connected = false
end

"""
Send a command to the instrument
"""
function command(inst::SerialSCPIInstrument, cmd::String)
    write(inst.serial_port, cmd*inst.delimiter)
    return nothing
end

"""
Perform a query to the instrument. Return String.
"""
function query(inst::SerialSCPIInstrument, cmd::String)
    command(inst, cmd)
    return readline(inst.serial_port)[1:end]
end

"""
Perform a query to the instrument. Parse result as type T.
"""
function query(inst::SerialSCPIInstrument, cmd::String, T::Type)
    a = query(inst, cmd)
    return parse(T, a)
end