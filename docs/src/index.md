# MPIMeasurements.jl

*A measurement platform for [MPI](https://en.wikipedia.org/wiki/) systems.*

This package provides tools for acquiring [MPI](https://en.wikipedia.org/wiki/Magnetic_particle_imaging) data by providing a composable platform for working with the scanner hardware. By the use of simple configuration files you can describe your hardware and run specific imaging protocols on it.

## Installation

Start julia and open the package mode by entering `]`. Then enter
```julia
add MPIMeasurements
```
This will install the packages `MPIMeasurements.jl` and all its dependencies.

## License / Terms of Usage

The source code of this project is licensed under the MIT license. This implies that
you are free to use, share, and adapt it. However, please give appropriate credit by citing the project.

## Community Guidelines

If you have problems using the software, find bugs, or have feature requests please use the [issue tracker](https://github.com/MagneticParticleImaging/MPIMeasurements.jl/issues) to contact us. For general questions we prefer that you contact the current maintainer directly by email.

We welcome community contributions to `MPIMeasurements.jl`. Simply create a [pull request](https://github.com/MagneticParticleImaging/MPIMeasurements.jl/pulls) with your proposed changes.

## Contributors

* [Tobias Knopp](https://www.tuhh.de/ibi/people/tobias-knopp-head-of-institute.html) (maintainer)
* TODO: Add missing persons
* [Jonas Schumacher](https://www.imt.uni-luebeck.de/institute/staff/jonas-schumacher.html)

## Manual Outline

```@contents
Pages = [
    "man/guide.md",
    "man/examples.md",
    "man/protocols.md",
    "man/sequences.md",
]
Depth = 1
```

## Library Outline

```@contents
Pages = ["lib/public.md", "lib/internals.md"]
```

### [Index](@id main-index)

```@index
Pages = ["lib/public.md"]
```