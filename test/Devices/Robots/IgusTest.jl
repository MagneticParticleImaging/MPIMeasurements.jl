# This test only runs if explicitly asked to via `julia --project test/runtests.jl "igus"`
if all_tests || "igus" in ARGS

  @testset "Igus robot device" begin
    @test true == true # Dummy test

  end

end