dir(scanner::MPIScanner) = @get_scratch!(name(scanner))
dir(protocol::Protocol) = joinpath(dir(scanner(protocol)), name(protocol))
file(protocol::Protocol, file::String) = joinpath(mkpath(dir(protocol)), file)
isfile(protocol::Protocol, name::String) = isfile(file(protocol, name))

function mmap!(protocol::Protocol, f::String, array::Array{T,N}) where {T, N}
    open(file(protocol, f), "w+") do io
        write(io, N)
        for s in size(array)
            write(io, s)
        end
        write(io, array)
    end
    return mmap(protocol, f, T)
end

function mmap(protocol::Protocol, f::String, eltype::Type{T}) where {T}
    io = open(file(protocol, f), "r+")
    N = Base.read(io, Int64)
    dims = []
    for i = 1:N
        push!(dims, Base.read(io, Int64))
    end
    return Mmap.mmap(io, Array{eltype,N}, tuple(dims...))
end