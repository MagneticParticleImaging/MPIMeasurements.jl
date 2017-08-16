@testset "Testing Positions submodule" begin
  pp = ParkPosition()
  @test typeof(pp) == ParkPosition
  @test supertype(typeof(pp)) == AbstractPosition
  cp = CenterPosition()
  @test typeof(cp) == CenterPosition
  @test supertype(typeof(cp)) == AbstractPosition

  shp = [3,3,3]
  fov = [3.0,3.0,3.0]u"mm"
  ctr = [0,0,0]u"mm"
  caG = CartesianGridPositions(shp,fov,ctr)
  @test MPIFiles.shape(caG) == shp
  @test MPIFiles.fieldOfView(caG) == fov
  @test MPIFiles.center(caG) == ctr
  #TODO following tests fail. dont know why
  #@test_throws BoundsError rG[0]
  #@test_throws BoundsError rG[28]
  @test caG[1] == [-1,-1,-1]u"mm"
  @test caG[2] == [0,-1,-1]u"mm"
  @test caG[3] == [1,-1,-1]u"mm"
  @test caG[4] == [-1,0,-1]u"mm"
  @test caG[27] == [1,1,1]u"mm"

  chG = ChebyshevGridPositions(shp,fov,ctr)
  @test MPIFiles.shape(chG) == shp
  @test MPIFiles.fieldOfView(chG) == fov
  @test MPIFiles.center(chG) == ctr
  #TODO following tests fail. dont know why
  #@test_throws BoundsError cG[0]
  #@test_throws BoundsError cG[28]
  @test chG[1] ≈ cos(π/6)*3/2*caG[1]
  @test chG[2] ≈ cos(π/6)*3/2*caG[2]
  @test chG[3] ≈ cos(π/6)*3/2*caG[3]
  @test chG[4] ≈ cos(π/6)*3/2*caG[4]
  @test chG[27] ≈ cos(π/6)*3/2*caG[27]

  mG = MeanderingGridPositions(caG)
  @test MPIFiles.shape(mG) == shp
  @test MPIFiles.fieldOfView(mG) == fov
  @test MPIFiles.center(mG) == ctr
  @test mG[1] == caG[1]
  @test mG[2] == caG[2]
  @test mG[3] == caG[3]
  @test mG[4] == caG[6]
  @test mG[7] == caG[7]
  @test mG[9] == caG[9]
  @test mG[10] == caG[18]
  @test mG[18] == caG[10]
  @test mG[19] == caG[19]
  @test mG[27] == caG[27]

  positions = [1 2 3 4; 0 1 2 3;-4 -3 -2 -1]u"mm"
  aG1 = ArbitraryPositions(positions)
  # the following 4 tests fail but should work
  #@test aG1 = [1,0,-4]u"mm"
  #@test aG1 = [2,1,-3]u"mm"
  #@test aG1 = [3,2,-2]u"mm"
  #@test aG1 = [4,3,-1]u"mm"
  aG2 = ArbitraryPositions(caG)
  @test aG2[1] ≈ caG[1]
  @test aG2[2] ≈ caG[2]
  @test aG2[27] ≈ caG[27]

  # the same seed yields the same sequence of points
  seed = UInt32(42)
  N = UInt(3)
  rG = UniformRandomPositions(N,seed,fov,ctr)
  @test rG[1] == [0.09954904813158394,-0.13791259323857274,-1.446939519855107]u"mm"
  @test rG[2] == [-0.9812009131891462,1.3767776289892044,1.4206979394110573]u"mm"
  @test rG[3] == [-0.5883911667396526,-0.9692742011014337,1.3707474722677764]u"mm"
  #TODO conversion methods dont work. Why?
  #rG = UniformRandomPositions(15,fov,ctr)

  # the following 2 tests fail but should work
  #@test_throws DomainError loadTDesign(pathtosrc,8,1)
  #@test_throws DomainError loadTDesign(pathtosrc,10,1)
  t = 1
  N = 2
  tDesign = loadTDesign(t,N, 5u"mm")
  @test length(tDesign) == N
  @test tDesign.T == t
  @test tDesign.radius == 5u"mm"
  @test any(tDesign.positions .== [1 -1; 0 0; 0 0])
  @test tDesign[1] == [5,0,0]u"mm"
  @test tDesign[2] == [-5,0,0]u"mm"

  @test length(caG) == prod(shp)
  @test length(chG) == prod(shp)
  @test length(mG) == prod(shp)
  @test length(aG1) == size(positions,2)
  @test length(aG2) == prod(shp)

  for (i,p) in enumerate(caG)
    @test p == caG[i]
  end
end
