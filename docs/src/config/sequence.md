# Sequence Parameters
## Magnetic Field
```@docs
MagneticField
```

## Channels
```@autodocs
Modules = [MPIMeasurements]
Filter = t -> typeof(t) === DataType && t <: MPIMeasurements.TxChannel
```

## Components
```@autodocs
Modules = [MPIMeasurements]
Filter = t -> typeof(t) === DataType && t <: MPIMeasurements.ElectricalComponent
```