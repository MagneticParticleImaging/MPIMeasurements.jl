## Scanner Construction
```@docs
MPIMeasurements.MPIScanner
MPIMeasurements.name
MPIMeasurements.configDir
MPIMeasurements.generalParams
MPIMeasurements.scannerBoreSize
MPIMeasurements.scannerFacility
MPIMeasurements.scannerManufacturer
MPIMeasurements.scannerName
MPIMeasurements.scannerTopology
MPIMeasurements.scannerGradient
MPIMeasurements.scannerDatasetStore
MPIMeasurements.defaultSequence
MPIMeasurements.defaultProtocol
```

## Device Handling
```@docs
MPIMeasurements.getDevices(::MPIScanner, ::Type{<:Device})
MPIMeasurements.getDevices(::MPIScanner, ::String)
MPIMeasurements.getDevice(::MPIScanner, ::Type{<:Device})
MPIMeasurements.getDeviceIDs
```

## Sequence Handling
```@docs
MPIMeasurements.Sequence(::MPIScanner, ::AbstractString)
MPIMeasurements.getSequenceList
```

## Protocol Handling
```@docs
MPIMeasurements.Protocol(::AbstractString, ::MPIScanner)
MPIMeasurements.getProtocolList
MPIMeasurements.execute(::MPIScanner, ::Protocol)
```