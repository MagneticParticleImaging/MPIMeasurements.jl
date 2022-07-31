export TCPSCPIInstrument

mutable struct TCPSCPIInstrument <: SCPIInstrument
    socket::TCPSocket
    is_connected::Bool
    delimiter::String

    function TCPSCPIInstrument(ip::IPAddr, port::Integer)
        return new(connect(ip, port), true, "\n")
    end
end

"""
Constructor interpreting the given `ip` string as a IPv4 address
"""
TCPSCPIInstrument(ip::String, port::Integer) = TCPSCPIInstrument(IPv4(ip), port)

function Base.close(inst::TCPSCPIInstrument)
    close(inst.socket)
    inst.is_connected = false
end

"""
Send a command to the instrument
"""
function command(inst::TCPSCPIInstrument, cmd::String)
  write(inst.socket, cmd*inst.delimiter)
end

"""
Perform a query to the instrument. Return String.
"""
function query(inst::TCPSCPIInstrument, cmd::String)
  command(inst, cmd)
  return readline(inst.socket)[1:end]
end

"""
Perform a query to the iunstrument. Parse result as type T.
"""
function query(inst::TCPSCPIInstrument, cmd::String, T::Type)
  a = query(inst, cmd)
  return parse(T, a)
end