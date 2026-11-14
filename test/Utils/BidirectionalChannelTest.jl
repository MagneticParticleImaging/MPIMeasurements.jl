@testset "BidirectionalChannel" begin
  a = BidirectionalChannel{Int}(2)
  b = BidirectionalChannel(a) # the other end: in and out swapped
  @test inChannel(b) === outChannel(a)
  @test outChannel(b) === inChannel(a)
  @test eltype(typeof(a)) == Int

  @test !isready(b)
  put!(a, 1)
  put!(a, 2)
  @test isready(b)
  @test !isready(a)
  @test MPIMeasurements.isfull(a) # the outgoing buffer holds two values
  @test !MPIMeasurements.isfull(b)
  @test take!(b) == 1
  @test take!(b) == 2

  put!(b, 3)
  wait(a)
  @test take!(a) == 3

  @test isopen(a)
  close(a)
  @test !isopen(a)
  @test !isopen(b)
end
