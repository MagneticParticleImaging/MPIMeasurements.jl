using Graphics: @mustimplement
using Unitful
import HDF5.name
import Base.length

# export types
export Clearance, Circle, Rectangle, Hexagon, Triangle
export Cylinder, Cuboid
export ScannerGeo, RobotSetup, RobotSafety, name, length, crosssection
export WantedVolume, DriveFieldAmplitude, GradientScan
# export functions
export convert2Unit, checkCoords, checkCoordsX, checkCoordsYZ, checkDeltaSample

# Robot Constants
const minClearance = 0.5Unitful.mm;
const regularBrukerScannerdiameter = 118.0Unitful.mm;
const maxDriveFieldAmplitude = 14.0Unitful.mT;
const maxWantedVolumeX = 300.0Unitful.mm;

struct Clearance
  distance::typeof(1.0Unitful.mm)
  Clearance(distance) = distance < minClearance ? error("Clearance below minimum") :
  new(distance)
end

abstract type Geometry end
@mustimplement name(geometry::Geometry)

abstract type TeachObj <: Geometry end
@mustimplement length(teachObj::TeachObj)
@mustimplement crosssection(teachObj::TeachObj)

struct Circle <: Geometry
  diameter::typeof(1.0Unitful.mm)
  name::String

  function Circle(diameter::typeof(1.0Unitful.mm), name::String)
    if diameter < 1.0Unitful.mm
      error("Circle does not fit in scanner...")
    else
      new(diameter, name)
    end
  end
end
name(geometry::Circle) = geometry.name

struct Cylinder <: TeachObj
    circle::Circle
    length::typeof(1.0Unitful.mm)
    name::String
    function Cylinder(circle::Circle,length::typeof(1.0Unitful.mm),name::String)
        if length < 1.0Unitful.mm
            error("Cylinder length too short...")
        else
            new(circle,length,name)
        end
    end
end
name(geometry::Cylinder) = geometry.name
length(teachObj::Cylinder) = teachObj.length
crosssection(teachObj::Cylinder) = teachObj.circle

struct Rectangle <: Geometry
  width::typeof(1.0Unitful.mm)
  height::typeof(1.0Unitful.mm)
  name::String

  function Rectangle(width::typeof(1.0Unitful.mm), height::typeof(1.0Unitful.mm), name::String)
    if width < 1.0Unitful.mm || height < 1.0Unitful.mm
      error("Rectangle does not fit in scanner...")
    else
      new(width, height, name)
    end
  end
end
name(geometry::Rectangle) = geometry.name

struct Cuboid <: TeachObj
    rectangle::Rectangle
    length::typeof(1.0Unitful.mm)
    name::String
    function Cuboid(rectangle::Rectangle, length::typeof(1.0Unitful.mm), name::String)
      if length < 1.0Unitful.mm
        error("Cuboid length too short...")
      else
        new(rectangle, length, name)
      end
    end
 end
 name(geometry::Cuboid) = geometry.name
 length(teachObj::Cuboid) = teachObj.length
 crosssection(teachObj::Cuboid) = teachObj.rectangle

struct Hexagon <: Geometry
  width::typeof(1.0Unitful.mm)
  height::typeof(1.0Unitful.mm)
  name::String
  function Hexagon(width::typeof(1.0Unitful.mm), height::typeof(1.0Unitful.mm), name::String)
    if width < 1.0Unitful.mm || height < 1.0Unitful.mm
      error("Hexagon does not fit in scanner...")
    else
      new(width, height, name)
    end
  end
end
name(geometry::Hexagon) = geometry.name

struct Triangle <: Geometry
  width::typeof(1.0Unitful.mm)
  height::typeof(1.0Unitful.mm)
  name::String

  function Triangle(width::typeof(1.0Unitful.mm), height::typeof(1.0Unitful.mm), name::String)
    if width < 1.0Unitful.mm || height < 1.0Unitful.mm
      error("Triangle does not fit in scanner...")
    else
      new(width, height, name)
    end
  end
end
name(geometry::Triangle) = geometry.name

struct ScannerGeo
  diameter::typeof(1.0Unitful.mm)
  name::String
  length::typeof(1.0Unitful.mm)
  teachObj::TeachObj
  function ScannerGeo(diameter::typeof(1.0Unitful.mm), name::String, length::typeof(1.0Unitful.mm), teachObj::TeachObj)
    if diameter < 1.0Unitful.mm || length < 1.0Unitful.mm
      error("ScannerGeometry is not possible...")
    else
      new(diameter, name, length, teachObj)
    end
  end
end

struct WantedVolume
     x_dim::typeof(1.0Unitful.mm)
     y_dim::typeof(1.0Unitful.mm)
     z_dim::typeof(1.0Unitful.mm)

     function WantedVolume(x_dim::typeof(1.0Unitful.mm), y_dim::typeof(1.0Unitful.mm), z_dim::typeof(1.0Unitful.mm))
       if x_dim > maxWantedVolumeX || y_dim > regularBrukerScannerdiameter || z_dim > regularBrukerScannerdiameter
         error("Your wanted volume is bigger than the scanner...")
       else
         new(x_dim, y_dim, z_dim)
       end
     end
end

struct DriveFieldAmplitude
  amp_x::typeof(1.0Unitful.mT)
  amp_y::typeof(1.0Unitful.mT)
  amp_z::typeof(1.0Unitful.mT)

  function DriveFieldAmplitude(amp_x::typeof(1.0Unitful.mT), amp_y::typeof(1.0Unitful.mT), amp_z::typeof(1.0Unitful.mT))
   if amp_x > maxDriveFieldAmplitude || amp_y > maxDriveFieldAmplitude || amp_z > maxDriveFieldAmplitude
     error("Ask Bruker for a higher drive field amplitude...")
   else
     new(amp_x, amp_y, amp_z)
   end
  end
end

struct GradientScan
  strength::typeof(1.0Unitful.T/Unitful.m)

  GradientScan(strength) = strength > 2.5Unitful.T/Unitful.m || strength < 0.1Unitful.T/Unitful.m ?
  error("Buy a new scanner which has more than 2.5T/m...:)") : new(strength)
end

mutable struct RobotSetup
  name::String
  objGeo::Geometry
  scannerGeo::ScannerGeo
  clearance::Clearance
end

"""
* validScannerGeos = [brukerCoil, mouseCoil, ratCoil, headCoil]
* validObjects = [deltaSample, hallSensor, mouseAdapter, samplePhantom]
* validRobotSetups = [dSampleRegularScanner, mouseAdapterRegularScanner, dSampleMouseScanner, mouseAdapterMouseScanner,
 dSampleRatScanner, mouseAdapterRatScanner, hallSensorRegularScanner, hallSensorMouseScanner, hallSensorRatScanner]
"""
function RobotSetup(params::Dict)
    receiveCoil = getfield(MPIMeasurements,Symbol(params["receiveCoil"]))
    robotMount = getfield(MPIMeasurements,Symbol(params["robotMount"]))
    clearance = getfield(MPIMeasurements,Symbol(params["clearance"]))
    return RobotSetup(params["setupName"],robotMount,receiveCoil,clearance)
end

"convert2unit(data,unit) converts the data array (tuples) without units to
      an array with length units."
function convert2Unit(data, unit::Unitful.Units{U ,Unitful.Dimensions{(Unitful.Dimension{:Length}(1//1),)}}) where U
         #create single coordinate vectors from data array and add the desired unit
         x_coord=[x[1] for x in data]*unit;
         y_coord=[x[2] for x in data]*unit;
         z_coord=[x[3] for x in data]*unit;
         #combine single vectors to array
         coord_array=hcat(x_coord,y_coord,z_coord);
end

"convert2unit(data,unit) converts the data array without units to
      an array with length units."
function convert2Unit(data::Array{T,2}, unit::Unitful.Units{U ,Unitful.Dimensions{(Unitful.Dimension{:Length}(1//1),)}}) where {T,U}
         if size(data, 2) != 3
           error("Wrong dimension...try array X x 3")
         end
         return data * unit;
end

checkCoords(robotSetup::RobotSetup, coord::Vector{typeof(1.0Unitful.mm)},minMaxRobotX::Vector{typeof(1.0Unitful.mm)})=checkCoords(robotSetup, [coord[1] coord[2] coord[3]], minMaxRobotX::Vector{typeof(1.0Unitful.mm)})
"checkCoords(robotSetup, coords; plotresults) is used to check if the chosen test coordinates are inside the allowed range
      of the roboter movement. If invalid points exist a list with all points will be presented
      to the user. Only the following test geometry types will be accepted: circle, rectangle, hexagon and triangle.
      The positions of the test objects will be plotted if at least one coordinate is invalid and plotresults=true."
function checkCoords(robotSetup::RobotSetup, coords::Array{typeof(1.0Unitful.mm),2},
     minMaxRobotX::Vector{typeof(1.0Unitful.mm)}; plotresults = false)
  geo = robotSetup.objGeo;
  scanner = robotSetup.scannerGeo;
  clearance = robotSetup.clearance;
  #initialize numPos variable
  numPos, dim=size(coords);
  if dim != 3
    error("Only 3-dimensinonal coordinates accepted!")
  end
  #initialize error vectors
  errorStatus = Array{Symbol}(undef, numPos, 3)
  errorX = Array{Any}(undef,numPos)
  errorY = Array{Any}(undef,numPos)
  errorZ = Array{Any}(undef,numPos)

  #initialize scanner radius
  scannerRad = scanner.diameter / 2;

for i=1:numPos

  x_i=coords[i, 1];
  y_i=coords[i, 2];
  z_i=coords[i, 3];

  # CheckCoordsX
  errorStatus[i, 1], errorX[i] = checkCoordsX(x_i, scanner, length(geo),
   minMaxRobotX[1], minMaxRobotX[2])

  # CheckCoordsYZ
  a,b,c = checkCoordsYZ(crosssection(geo), scannerRad, y_i, z_i, clearance)

  errorStatus[i, 2:3] .= a
  errorY[i] = b
  errorZ[i] = c

end #for numPos
  #create coordinate table with errors
  table=hcat(errorStatus, coords, errorX, errorY, errorZ);
  #table headlines
  headline=["Status x" "Status y" "Status z" "x" "y" "z" "delta_x" "delta_y" "delta_z"];
  #create final table
  coordTable = vcat(headline, table);
  errBool = (LinearIndices(errorStatus))[findall(x-> x == :INVALID, errorStatus)]
  if isempty(errBool)
     display("All coordinates are safe!");
     return coordTable;
  else
     display("Used geometry: $(geo.name)")
     display("Used scanner diameter: $(scanner.name)")
     display("Following coordinates are dangerous and NOT valid!");
     errorIndecies,  = ind2sub(errorStatus, errBool)
     errorIndecies = vec(union(errorIndecies))
     errorTable = coordTable[errorIndecies.+1, :];
     display(errorTable)

     plotresults ? plotSafetyErrors(errorIndecies, coords, robotSetup, errorStatus) : "Plotting not chosen...";
     throw(CoordsError("Some coordinates exceeded their range!",coordTable));
  end
end #function



function checkCoordsX(posX::typeof(1.0Unitful.mm), scanner::ScannerGeo,
     objLength::typeof(1.0Unitful.mm), minRobotX::typeof(1.0Unitful.mm),
     maxRobotX::typeof(1.0Unitful.mm))
     scannerLength = scanner.length
     teachObjLength = length(scanner.teachObj)
     # assumption: (0,0,0) is teached with teachObj at the center of the scannerLength
     # So robot can move half of scannerLength
     # plus the difference length between teaching obj and current used object
     # minRobotX is dependent of the current teaching position
     minPosX = max(minRobotX, (-scannerLength/2) + objLength - teachObjLength)
     if posX < minPosX
         return :INVALID, ustrip(posX-minPosX)
     elseif posX > maxRobotX
         return :INVALID, ustrip(maxRobotX-posX)
     else
         return :VALID, zero(0.0)
     end
end

function checkCoordsYZ(geo::Circle, scannerRad::typeof(1.0Unitful.mm), posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm),clearance::Clearance)
    delta = scannerRad - sqrt(posY^2+posZ^2) - geo.diameter/2;
    delta_y = (abs(posY)+geo.diameter/2*sin(atan(abs(posY/posZ)))) - scannerRad*sin(atan(abs(posY/posZ)));
    delta_z = (abs(posZ)+geo.diameter/2*cos(atan(abs(posY/posZ)))) - scannerRad*cos(atan(abs(posY/posZ)));

    if delta > clearance.distance
       return :VALID, zero(0.0),zero(0.0)
    else
       return :INVALID, ustrip(delta_y), ustrip(delta_z)
    end #if clearance
end

function checkCoordsYZ(geo::Rectangle, scannerRad::typeof(1.0Unitful.mm), posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm),clearance::Clearance)
    delta_y=(abs(posY)+geo.width/2)-scannerRad*sin(atan((abs(posY)+geo.width/2)/(abs(posZ)+geo.height/2)));
    delta_z=(abs(posZ)+geo.height/2)-scannerRad*cos(atan((abs(posY)+geo.width/2)/(abs(posZ)+geo.height/2)));

    if clearance.distance > delta_y && clearance.distance > delta_z
       return :VALID, zero(0.0), zero(0.0)
    else
       return :INVALID, ustrip(delta_y), ustrip(delta_z)
    end #if clearance
end

function checkCoordsYZ(geo::Hexagon, scannerRad::typeof(1.0Unitful.mm), posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm),clearance::Clearance)
    #approximate hexagon by circle
    if geo.width > geo.height
       hex_radius = geo.width/2;
    else
       hex_radius = geo.height/2;
    end
    #check distances
    delta = scannerRad - sqrt(posY^2+z_i^2)-hex_radius;
    delta_y = (abs(posY)+hex_radius*sin(atan(abs(posY/posZ)))) - scannerRad*sin(atan(abs(posY/posZ)));
    delta_z = (abs(posZ)+hex_radius*cos(atan(abs(posY/posZ)))) - scannerRad*cos(atan(abs(posY/posZ)));

    if delta > clearance.distance
       return :VALID, zero(0.0), zero(0.0)
    else
       return :INVALID, ustrip(delta_y), ustrip(delta_z)
    end #if clearance
end

function checkCoordsYZ(geo::Triangle, scannerRad::typeof(1.0Unitful.mm), posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm),clearance::Clearance)
    #following code only for symmetric triangles / center of gravity = center of plug adapter
    perimeter = sqrt(geo.width^2/4+geo.height^2)/(2*sin(atan(2*geo.height/geo.width)));

    #define new z coordinate, since center of gravity is not equal to center of perimeter circle
    z_new=posZ+((2/3)*geo.height-perimeter);

    delta = scannerRad - sqrt(posY^2+z_new^2)-perimeter;
    delta_y = (abs(posY)+perimeter*sin(atan(abs(posY/z_new))))-scannerRad*sin(atan(abs(posY/z_new)));
    delta_z = (abs(z_new)+perimeter*cos(atan(abs(posY/z_new))))-scannerRad*cos(atan(abs(posY/z_new)));

    if delta > clearance.distance
       return :VALID, zero(0.0), zero(0.0)
    else
       return :INVALID,ustrip(delta_y), ustrip(delta_z)
    end #if clearance
end

struct CoordsError <: Exception
    message::String
    coordTable
end

function checkDeltaSample(scanDiameter::typeof(1.0Unitful.mm),y::typeof(1.0Unitful.mm),z::typeof(1.0Unitful.mm), clearance::typeof(1.0Unitful.mm)=1.0Unitful.mm)
    deltaSample = Circle(10.0Unitful.mm, "Delta sample");
    scanRad = scanDiameter/2;
    dSRadius = deltaSample.diameter/2;
    delta = scanRad - sqrt(y^2+z^2) - (dSRadius);
    delta_y = -(abs(y)+dSRadius*sin(atan(abs(y/z)))) + scanRad*sin(atan(abs(y/z)));
    delta_z = -(abs(z)+dSRadius*cos(atan(abs(y/z)))) + scanRad*cos(atan(abs(y/z)));
    space_z= sqrt((scanRad-dSRadius-1Unitful.mm)^2-y^2)-z;
    space_y= sqrt((scanRad-dSRadius-1Unitful.mm)^2-z^2)-y;
    if delta > clearance
        return :VALID, delta, space_y,space_z,delta_y, delta_z
    else
        return :INVALID, delta, space_y,space_z,delta_y, delta_z
    end
end

function plotSafetyErrors(errorIndecies, coords, robotSetup, errorStatus)
  geo = robotSetup.objGeo;
  scannerRad = robotSetup.scannerGeo.diameter / 2;
  for i = 1:length(errorIndecies)
    y_i=coords[i, 2];
    z_i=coords[i, 3];
    t=range(0,stop=2,length=200);

    x_scanner = ustrip(scannerRad)*cos(t*pi);
    y_scanner = ustrip(scannerRad)*sin(t*pi);

  if typeof(geo) == Circle
    if errorStatus[i, 2] == :INVALID
    x_geometry=ustrip(geo.diameter/2)*cos(t*pi)+ustrip(y_i);
    y_geometry=ustrip(geo.diameter/2)*sin(t*pi)+ustrip(z_i);

    # p=Plots.plot(title="Plot results - $(geo.name) position - Set $i", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal);
    # Plots.plot!(x_scanner,y_scanner, color=:blue)
    # Plots.plot!(x_geometry,y_geometry, color=:red)
    # gui()
    end

  elseif typeof(geo) == Rectangle
    if errorStatus[i, 2:3] == :INVALID
    #Create rectangle corner points
    #point bottom left
    p_bl=ustrip([y_i-geo.width/2, z_i-geo.height/2]);
    #point upper left
    p_ul=ustrip([y_i-geo.width/2, z_i+geo.height/2]);
    #point upper right
    p_ur=ustrip([y_i+geo.width/2, z_i+geo.height/2]);
    #point bottom right
    p_br=ustrip([y_i+geo.width/2, z_i-geo.height/2]);

    # p=Plots.plot(title="Plot results - $(geo.name) position - Set $i", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal);
    # p=Plots.plot!(x_scanner,y_scanner,[p_bl[1],p_ul[1]],[p_bl[2],p_ul[2]],[p_ul[1],p_ur[1]],[p_ul[2],p_ur[2]],
    #        [p_ur[1],p_br[1]],[p_ur[2],p_br[2]],[p_br[1],p_bl[1]],[p_br[2],p_bl[2]],color="blue");
    # gui()
    end

  elseif typeof(geo) == Hexagon
    if errorStatus[i, 2:3] == :INVALID

    if geo.width > geo.height
       hex_radius = geo.width/2;
    else
       hex_radius = geo.height/2;
    end

    x_geometry = ustrip(hex_radius)*cos(t*pi)+ustrip(y_i);
    y_geometry = ustrip(hex_radius)*sin(t*pi)+ustrip(z_i);

    if geo.width>geo.height
       #Create hexagon corner points (tips are left and right)
       #point left
       p_l = ustrip([y_i-geo.width/2, z_i]);
       #point top left
       p_tl = ustrip([y_i-geo.width/4, z_i+geo.height/2]);
       #point top right
       p_tr = ustrip([y_i+geo.width/4, z_i+geo.height/2]);
       #point right
       p_r = ustrip([y_i+geo.width/2, z_i]);
       #point bottom right
       p_br = ustrip([y_i+geo.width/4, z_i-geo.height/2]);
       #point bottom left
       p_bl = ustrip([y_i-geo.width/4, z_i-geo.height/2]);

      #  p=Plots.plot(title="Plot results - $(geo.name) position - Set $i", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal);
      #  Plots.plot!(x_scanner,y_scanner,x_geometry,y_geometry,[p_l[1],p_tl[1]],[p_l[2],p_tl[2]],
      #         [p_tl[1],p_tr[1]],[p_tl[2],p_tr[2]],[p_tr[1],p_r[1]],[p_tr[2],p_r[2]],
      #         [p_r[1],p_br[1]],[p_r[2],p_br[2]],[p_br[1],p_bl[1]],[p_br[2],p_bl[2]],
      #         [p_bl[1],p_l[1]],[p_bl[2],p_l[2]],color="blue");
      #  gui()

    else
       #Create hexagon corner points (tips are on top and at bottom)
       #point left bottom
       p_lb=ustrip([y_i-geo.width/2, z_i-geo.height/4]);
       #point left top
       p_lt=ustrip([y_i-geo.width/2, z_i+geo.height/4]);
       #point top
       p_t=ustrip([y_i, z_i+geo.height/2]);
       #point right top
       p_rt=ustrip([y_i+geo.width/2, z_i+geo.height/4]);
       #point right bottom
       p_rb=ustrip([y_i+geo.width/2, z_i-geo.height/4]);
       #point bottom
       p_b=ustrip([y_i, z_i-geo.height/2]);

      #  p=Plots.plot(title="Plot results - $(geo.name) position - Set $i", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal);
      #  Plots.plot!(x_scanner,y_scanner,x_geometry,y_geometry,[p_lb[1],p_lt[1]],[p_lb[2],p_lt[2]],
      #         [p_lt[1],p_t[1]],[p_lt[2],p_t[2]],[p_t[1],p_rt[1]],[p_t[2],p_rt[2]],
      #         [p_rt[1],p_rb[1]],[p_rt[2],p_rb[2]],[p_rb[1],p_b[1]],[p_rb[2],p_b[2]],
      #         [p_b[1],p_lb[1]],[p_b[2],p_lb[2]],color="blue");
      #  gui()
    end
    end

  elseif typeof(geo) == Triangle
    if errorStatus[i, 2:3] == :INVALID
    perimeter=sqrt(geo.width^2/4+geo.height^2)/(2*sin(atan(2*geo.height/geo.width)));

    z_new=z_i+((2/3)*geo.height-perimeter);

    x_geometry=ustrip(perimeter)*cos(t*pi)+ustrip(y_i);
    y_geometry=ustrip(perimeter)*sin(t*pi)+ustrip(z_new);

    #Create triangle corner points
    #point bottom left
    p_bl=ustrip([y_i-geo.width/2, z_i-geo.height/3]);
    #upper point
    p_u=ustrip([y_i, z_i+2/3*geo.height]);
    #point bottom right
    p_br=ustrip([y_i+geo.width/2, z_i-geo.height/3]);

    # p=Plots.plot(title="Plot results - $(geo.name) position - Set $i", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal);
    # Plots.plot!(x_scanner,y_scanner,x_geometry,y_geometry,[p_bl[1],p_u[1]],[p_bl[2],p_u[2]],
    #        [p_u[1],p_br[1]],[p_u[2],p_br[2]],[p_br[1],p_bl[1]],[p_br[2],p_bl[2]],color="blue");
    # gui()
    end #if error_string
  end #for
  end #if cases
end
