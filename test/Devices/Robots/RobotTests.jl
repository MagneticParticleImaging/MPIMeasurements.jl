using InteractiveUtils: subtypes

@testset "Robot" begin
  @testset "test $rob_type interface" for rob_type in subtypes(Robot)
    par_type = eval(Symbol(string(rob_type)*"Params"))
    params = par_type()
    rob = rob_type(deviceID="test", params=params, dependencies=Dict{String, Union{Device, Missing}}())

    degrees = dof(rob)
    @test degrees isa Int

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
    include("DummyRobotTests.jl")
  end

  @testset "SimulatedRobot" begin
    include("SimulatedRobotTests.jl")
  end

  if "igus" in ARGS
    @testset "IgusRobot" begin
    include("IgusRobotTests.jl")
    end
  end

  if "isel" in ARGS
    @testset "IselRobot" begin
    include("IselRobotTests.jl")
    end
  end

  if "brukerrobot" in ARGS
    @testset "BrukerRobot" begin
    include("BrukerRobotTests.jl")
    end
  end
end