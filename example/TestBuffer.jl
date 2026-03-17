using MPIMeasurements
using LibSerialPort
# Import for SerialDevice and query function
using MPIMeasurements: SerialDevice, query

sd = SerialDevice("/dev/ttyACM0"; nstopbits=1, delim_read="\r", ndatabits=8, baudrate=250000, timeout_ms=2000, parity=LibSerialPort.SP_PARITY_NONE, delim_write="\r")

response = query(sd, "*DUMMY?#")

bytesInResponse = length(response)
println("Received $bytesInResponse bytes")