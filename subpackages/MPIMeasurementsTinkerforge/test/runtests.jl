using Test
using Aqua
using PyCall

# MPIMeasurementsTinkerforge loads PyTinkerforge, which needs the Python module
# `tinkerforge` in the Python used by PyCall. If the module is missing,
# PyTinkerforge tries to pip-install it through Conda.jl while loading, which
# currently fails (https://github.com/JuliaPy/Conda.jl/issues/265). Therefore
# check for the module before loading the package.
tinkerforgeAvailable = pyimport("importlib.util").find_spec("tinkerforge") !== nothing

if tinkerforgeAvailable
  using MPIMeasurementsTinkerforge

  @testset "MPIMeasurementsTinkerforge" begin
    @testset "Aqua" begin
      Aqua.test_all(MPIMeasurementsTinkerforge, ambiguities=false, stale_deps=false) # Stale deps deactivated due to errors with python packages
    end

    # Add tests here
  end
else
  @warn """
  MPIMeasurementsTinkerforge could not be tested: the Python module `tinkerforge` is not
  installed in the Python used by PyCall ($(PyCall.python)).
  PyTinkerforge would try to install it automatically via Conda.jl when it is loaded, but
  that currently fails (https://github.com/JuliaPy/Conda.jl/issues/265).
  To fix this, install the module manually into that Python and run the tests again:

      "$(PyCall.python)" -m pip install tinkerforge
  """
  @testset "MPIMeasurementsTinkerforge" begin
    @test_broken tinkerforgeAvailable
  end
end
