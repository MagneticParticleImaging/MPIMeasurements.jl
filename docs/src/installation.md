# Installation
The realization of a new MPI system with `MPIMeasurements.jl` requires the installation and preparation of three components. The first component is the Julia framework itself, the second is a set of configuration files associated from which the framework insantiates a system and the third is a package containing concrete `Device` and `Protocol` implementations used by the system. 

## Julia Package
To use the framework, you need to install to install `MPIMeasurements.jl` within Julia. To this end, start julia and open the package mode by entering `]`. Then enter
```julia
add MPIMeasurements
```
This will install the latest version of `MPIMeasurements.jl` and all its dependencies. Alternatively one can also use 
```julia
dev MPIMeasurements
```
to add the package in development mode. This installs a full clone of the packages repository, which can then be changed and adapted. However, in this latter case the version control is fully the users responsiblity.

To use specific versions of the framework or to read more information about package mangement, please consult the [Pkg documentation](https://pkgdocs.julialang.org/dev/managing-packages/#Adding-packages).

## Scanner Configuration Files
Each `Scanner` in `MPIMeasurements.jl` is associated with a directory containing a set of configuration files in the [TOML](https://toml.io/en/) format. Per default the framwork searches for these directories in two locations: The `config` located in the packages file structure itself and the users home directory under `.mpi/Scanners`. However, it is also possible to add new configuration paths that are considered by the framework.

It is recommended that a user creates the following directory structure in their home directory:
```
.mpi/
├── Scanners/
│   └── <Example Scanner Name>
│   └── ...
└── Logs/
```
It is also recommended to place the individual scanner directories or the entire `Scanners/` subdirectory under version control.

## (Private) Device and Protocol Implementations
`MPIMeasurements.jl` instantiates a `Scanner` based on its configuration files. These files describe the used `Device`s and their dependencies and in turn `Device` implementations are constructed. While `MPIMeasurements` itself contains several concrete `Device` and `Protocol` implementations, it is also possible to add (and develop) other (private) Julia packages that contain and extend more implementations.