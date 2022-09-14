export CoolingControllerParams, CoolingController

# TODO: Add parsing for linked devices, controller step calculation, etc.

Base.@kwdef mutable struct CoolingControllerParams <: DeviceParams
  
end
CoolingControllerParams(dict::Dict) = params_from_dict(CoolingControllerParams, dict)

Base.@kwdef mutable struct CoolingController <: VirtualDevice
  @add_device_fields CoolingControllerParams


end

function init(coolCont::CoolingController)
  @info "Initializing CoolingController with ID `$(coolCont.deviceID)`."
  coolCont.present = true
end

neededDependencies(::CoolingController) = []
optionalDependencies(::CoolingController) = [Motor]

function setup(coolCont::CoolingController, seq::Sequence)
  

end