
if "lakeshore" in ARGS
  @testset "LakeShore" begin
    include("LakeShoreTest.jl")
  end
end

if "lakeshoref71" in ARGS
  @testset "LakeShoreF71" begin
    include("LakeShoreF71Test.jl")
  end
end