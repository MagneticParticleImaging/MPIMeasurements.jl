@testset "test $type interface" for type in ["DummyRobot", "SimulatedRobot", "IgusRobot"]
    rob_type = eval(Symbol(type))
    par_type = eval(Symbol(type*"Params"))
    params = par_type()
    rob = rob_type("test",params)
    
    degrees = dof(rob)
    @test degrees isa Int
    pos = getPosition(rob)
    @test pos isa Vector{<:Unitful.Length}
    @test length(pos) == degrees

    axes = axisRange(rob)
    @test axes isa Vector{<:Vector{<:Unitful.Length}}
    @test length(axes) == degrees
    @test length(axes[1]) == 2
    for i in 1:degrees
        @test axes[i][1]<=axes[i][2]
    end

    def_vel = defaultVelocity(rob)
    @test def_vel isa Union{Vector{<:Unitful.Velocity},Nothing}
    if def_vel !== nothing
        @test length(def_vel) == degrees
    end
end

@testset "DummyRobot" begin
  include("DummyRobot.jl")
end

@testset "SimulatedRobot" begin
  include("SimulatedRobot.jl")
end

#=
@testset "IgusRobot" begin
  include("IgusRobot.jl")
end
=#

