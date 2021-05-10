using InteractiveUtils: subtypes

@testset "test $rob_type interface" for rob_type in subtypes(Robot)
    par_type = eval(Symbol(string(rob_type)*"Params"))
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

if "igus" in ARGS
    @testset "IgusRobot" begin
    include("IgusRobot.jl")
    end
end


