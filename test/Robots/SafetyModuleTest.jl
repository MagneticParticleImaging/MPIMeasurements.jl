using MPILib
using MPIFiles
using Base.Test
using Unitful
using Plots

println(@inferred Clearance(2.0u"mm"))
println(@test_throws ErrorException Clearance(0.4u"mm"))
println(@test_throws ErrorException Circle(-0.5u"mm","test"))
println(@test_throws ErrorException Circle(120.0u"mm","test2"))
println(@test_throws ErrorException ScannerGeo(0.5u"mm","test3"))
println(@test_throws ErrorException ScannerGeo(118.5u"mm","test3"))
println(@test_throws ErrorException DriveFieldAmplitude(15.0u"mT", 14.0u"mT", 14.0u"mT"))
println(@test_throws ErrorException GradientScan(2.6u"T/m"))

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

p_mm = convert2Unit(pos, u"mm");
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
p2_mm = convert2Unit(pos2, u"mm");
table = checkCoords(mouseAdapterRegularScanner, p2_mm, plotresults = false)


t=ones(1)*100*u"s"
@test_throws SystemError moveRobotAndAcquireData(mouseAdapterRegularScanner, p2_mm, t)

coords=rand(5,3)*u"mm";
lingerTime=rand(5)*u"s";
saveRobotCommandsAsHDF("test.hdf",coords, lingerTime);
@test_throws SystemError moveRobotAndAcquireData(mouseAdapterRegularScanner,"test.hdf");
coordsLoad, lingerTimeLoad =loadRobotCommandsFromHDF("test.hdf");
@test coords==coordsLoad;
@test lingerTime==lingerTimeLoad;
rm("test.hdf")

@test_throws Base.UVError moveRobot(mouseAdapterRegularScanner, (3.0u"mm",4.0u"mm",5.0u"mm"))
