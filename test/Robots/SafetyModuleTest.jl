using MPILib
using MPIFiles
using Base.Test
using Unitful
using Plots

println(@inferred Clearance(2.0Unitful.mm))
println(@test_throws ErrorException Clearance(0.4Unitful.mm))
println(@test_throws ErrorException Circle(-0.5Unitful.mm,"test"))
println(@test_throws ErrorException Circle(120.0Unitful.mm,"test2"))
println(@test_throws ErrorException ScannerGeo(0.5Unitful.mm,"test3"))
println(@test_throws ErrorException ScannerGeo(118.5Unitful.mm,"test3"))
println(@test_throws ErrorException DriveFieldAmplitude(15.0Unitful.mT, 14.0Unitful.mT, 14.0Unitful.mT))
println(@test_throws ErrorException GradientScan(2.6Unitful.T/Unitful.m))

pos=Array{Tuple{Float64,Float64,Float64},1}(12)
# x-coordinate test
pos[1]=(-85, 0.0, 0.0)
pos[2]=(-85 - 0.001, 0.0, 0.0)
pos[3]=(220, 0.0, 0.0)
pos[4]=(225 + 0.001, 0.0, 0.0)
# y coordinate test
pos[5]=(0.0, 28.9, 0.0)
pos[6]=(0.0, 29.0, 0.0)
pos[7]=(0.0, -28.9, 0.0)
pos[8]=(0.0, -29.0, 0.0)
# z coordinate test
pos[9]=(0.0, 0.0, 28.9)
pos[10]=(0.0, 0.0, 29.0)
pos[11]=(0.0, 0.0, -28.9)
pos[12]=(0.0, 0.0, -29.0)

p_mm = convert2Unit(pos, Unitful.mm);
p_cm = convert2Unit(pos, u"cm");

display(p_mm);

try
 table = checkCoords(mouseAdapterRegularScanner, p_mm, plotresults = false)
catch ex
  display(ex.message)
  coords=ex.coordTable
  @test coords[2,1] == :VALID
  @test coords[3,1] == :INVALID
  @test coords[4,1] == :VALID
  @test coords[5,1] == :INVALID
end
@test_throws MethodError checkCoords(mouseAdapterRegularScanner, p_cm, plotresults = true)


pos2=Array{Tuple{Float64,Float64,Float64},1}(1)
pos2[1]=(-85, 0.0, 0.0)
p2_mm = convert2Unit(pos2, Unitful.mm);
table = checkCoords(mouseAdapterRegularScanner, p2_mm, plotresults = false)


t=ones(1)*100*Unitful.s
@test_throws SystemError moveRobotAndAcquireData(mouseAdapterRegularScanner, p2_mm, t)

coords=rand(5,3)*Unitful.mm;
lingerTime=rand(5)*Unitful.s;
saveRobotCommandsAsHDF("test.hdf",coords, lingerTime);
@test_throws SystemError moveRobotAndAcquireData(mouseAdapterRegularScanner,"test.hdf");
coordsLoad, lingerTimeLoad =loadRobotCommandsFromHDF("test.hdf");
@test coords==coordsLoad;
@test lingerTime==lingerTimeLoad;
rm("test.hdf")

@test_throws Base.UVError moveRobot(mouseAdapterRegularScanner, (3.0Unitful.mm,4.0Unitful.mm,5.0Unitful.mm))
