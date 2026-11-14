# Tests

The tests need no hardware and no network. Devices are either simulated or replaced
by the test devices in `TestDevices.jl`; scanner configurations live in `TestConfigs/`.

## Running the tests

From a checkout of the repository, run the tests in a temporary environment so that
nothing is added to your own environments:

```julia
using Pkg
Pkg.activate(temp = true)
Pkg.develop(path = "path/to/MPIMeasurements.jl")
Pkg.test("MPIMeasurements")
```

A full run takes a few minutes, most of it for compilation.

## Measuring coverage

Pass `coverage = true` to write `*.cov` files next to the source files:

```julia
Pkg.test("MPIMeasurements"; coverage = true)
```

and summarize them with [CoverageTools.jl](https://github.com/JuliaCI/CoverageTools.jl),
e.g. in another temporary environment:

```julia
using Pkg
Pkg.activate(temp = true)
Pkg.add("CoverageTools")
using CoverageTools
coverage = process_folder("path/to/MPIMeasurements.jl/src")
covered, total = get_summary(coverage)
println("$covered of $total lines covered ($(round(100 * covered / total, digits = 1)) %)")
clean_folder("path/to/MPIMeasurements.jl") # removes the *.cov files again
```

The numbers differ slightly from those reported by Codecov in CI.

## Layout

| Directory    | Content                                                        |
|--------------|----------------------------------------------------------------|
| `Scanner/`   | Scanner construction from the configurations in `TestConfigs/` |
| `Devices/`   | Device tests with simulated devices                            |
| `Sequences/` | Sequence loading, accessors, channels; fixtures in `Sequences/TOML/` |
| `Storage/`   | Measurement buffers and MDF assembly                           |
| `Utils/`     | Configuration parsing, coordinates, channels, memory-mapped files |

Known bugs in the package are marked with `@test_broken` and a comment describing the
problem. When fixing one, turn the assertion into a normal `@test`.
