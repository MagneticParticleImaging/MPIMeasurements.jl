export ServerDevice

""" Server Device"""
@compat struct ServerDevice{T<:Device}
  connectionName::String
end
