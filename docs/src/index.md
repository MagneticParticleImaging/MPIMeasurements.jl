# MPIMeasurements.jl

*A measurement and instrumentation framework for magnetic particle imaging ([MPI](https://en.wikipedia.org/wiki/Magnetic_particle_imaging)) and magnetic particle spectroscopy systems.*

## Introduction

This package provides tools for acquiring [MPI](https://en.wikipedia.org/wiki/Magnetic_particle_imaging) data by providing a composable representation for working with the scanner hardware. With the use of simple configuration files you can describe your hardware and run specific imaging protocols on it. The project is designed to be expanded to new systems through community development and component reuse.

The main components of the project are:
* `Scanner`, a composition of devices representing the hardware
* `Devices`, generic interfaces and implementations to/of hard- and software components of a scanner
* `Sequences`, abstract representation of magnetic fields and acquisition parameters
* `Protocols`, complex measurements procedures, that can be executed in scripts, GUIs or the Julia REPL

## License / Terms of Usage

The source code of this project is licensed under the MIT license. This implies that
you are free to use, share, and adapt it. However, please give appropriate credit by citing the project.

## Community Guidelines

If you have problems using the software, find bugs, or have feature requests please use the [issue tracker](https://github.com/MagneticParticleImaging/MPIMeasurements.jl/issues) to contact us. For general questions we prefer that you contact the current maintainers directly by email.

We welcome community contributions to `MPIMeasurements.jl`. Simply create a [pull request](https://github.com/MagneticParticleImaging/MPIMeasurements.jl/pulls) with your proposed changes.

## Maintainer

* [Tobias Knopp](https://www.tuhh.de/ibi/people/tobias-knopp-head-of-institute.html)
* [Niklas Hackelberg](https://www.tuhh.de/ibi/people/niklas-hackelberg.html)
* [Jonas Schumacher](https://www.imt.uni-luebeck.de/institute/staff/jonas-schumacher.html)