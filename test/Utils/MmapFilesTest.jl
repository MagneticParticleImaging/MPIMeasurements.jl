@testset "Memory-mapped files" begin
  # Mapped files stay open while the arrays are alive, which blocks removing them on
  # Windows, so the directory is left to the cleanup of mktempdir at exit
  dir = mktempdir()
  protocol = TempDirProtocol(dir)
  @test MPIMeasurements.file(protocol, "data.bin") == joinpath(dir, "data.bin")
  @test !MPIMeasurements.isfile(protocol, "data.bin")

  # Writing an array stores its dimensions in a header and maps the data
  array = reshape(Float32.(1:24), 2, 3, 4)
  mapped = MPIMeasurements.mmap!(protocol, "data.bin", array)
  @test MPIMeasurements.isfile(protocol, "data.bin")
  @test mapped == array
  @test size(mapped) == (2, 3, 4)
  # Header: number of dimensions and the dimensions as Int64, then the data
  @test filesize(joinpath(dir, "data.bin")) == 4 * 8 + 24 * 4

  # Mapping the file again gives the same data, changes are shared
  again = MPIMeasurements.mmap(protocol, "data.bin", Float32)
  @test again == array
  mapped[1, 1, 1] = 100
  MPIMeasurements.Mmap.sync!(mapped)
  @test again[1, 1, 1] == 100

  # Allocating by element type and size gives a zero-filled array
  zeroed = MPIMeasurements.mmap!(protocol, "zeros.bin", ComplexF64, (3, 2))
  @test size(zeroed) == (3, 2)
  @test eltype(zeroed) == ComplexF64
  @test all(iszero, zeroed)
  @test size(MPIMeasurements.mmap!(protocol, "vector.bin", Int16, [5])) == (5,)

  @testset "Mapping does not leave the file open" begin
    # Number of open handles (Windows) or file descriptors (Linux) of this process
    function openHandleCount()
      if Sys.iswindows()
        count = Ref{UInt32}(0)
        process = ccall((:GetCurrentProcess, "kernel32"), stdcall, Ptr{Cvoid}, ())
        ccall((:GetProcessHandleCount, "kernel32"), stdcall, Int32, (Ptr{Cvoid}, Ref{UInt32}), process, count) != 0 || error("GetProcessHandleCount failed")
        return Int(count[])
      elseif Sys.islinux()
        return length(readdir("/proc/self/fd"))
      end
      return nothing
    end
    # On Windows each mapped array holds the handle of its file mapping object
    handlesPerMapping = Sys.iswindows() ? 1 : 0

    numMappings = 20
    arrays = []
    # Garbage collection would close leaked streams and hide them from the count
    GC.enable(false)
    before, after = try
      countBefore = openHandleCount()
      for i in 1:numMappings
        push!(arrays, MPIMeasurements.mmap(protocol, "data.bin", Float32))
      end
      countBefore, openHandleCount()
    finally
      GC.enable(true)
    end
    if isnothing(before)
      @test_skip after - before <= numMappings * handlesPerMapping
    else
      @test after - before < numMappings * (handlesPerMapping + 1)
    end
    @test all(==(mapped), arrays)
  end
end
