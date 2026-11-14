const sequenceFixtureDir = joinpath(@__DIR__, "TOML")
sequenceFixture(name) = joinpath(sequenceFixtureDir, name)
loadFixtureDict(name) = MPIMeasurements.TOML.parsefile(sequenceFixture(name))

@testset "Sequences" begin
  include("WaveformTests.jl")
  include("SequenceLoadingTests.jl")
  include("SequenceAccessorTests.jl")
  include("ChannelTests.jl")
  include("SequenceErrorTests.jl")
end
