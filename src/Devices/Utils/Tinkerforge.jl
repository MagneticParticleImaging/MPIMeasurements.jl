

Base.@kwdef mutable struct TinkerforgeConnection
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  connection

  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedGaussMeterParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

self.ip_con = IPConnection()
            self.ip_con.connect(self.HOST, self.PORT)
