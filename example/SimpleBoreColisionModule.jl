using Plots

function plotSafetyErrors(cm::SimpleBoreCollisionModule, errorIndices::Vector{Int}, coords::AbstractMatrix{<:Unitful.Length})
  geo = cm.params.objGeometry;
  scannerRad = cm.params.scannerDiameter / 2;
  
  t = range(0, stop=2, length=200);

  x_scanner = scannerRad * cos.(t * pi);
  y_scanner = scannerRad * sin.(t * pi);
  x_scanner2 = (scannerRad - cm.params.clearance.distance) * cos.(t * pi);
  y_scanner2 = (scannerRad - cm.params.clearance.distance) * sin.(t * pi);
  
  fig = Plots.plot(title="Plot results - $(geo.name) positions", xlabel="y [mm]", ylabel="z [mm]", aspect_ratio=:equal)
  Plots.plot!(ustrip.(u"mm", x_scanner), ustrip.(u"mm", y_scanner), color=:blue, label="scanner")
  Plots.plot!(ustrip.(u"mm", x_scanner2), ustrip.(u"mm", y_scanner2), color=:yellow, label="scanner, with clearance")
  for i = errorIndices
    y_i = coords[i, 2];
    z_i = coords[i, 3];
    

    if typeof(geo) == Circle
      x_geometry = geo.diameter / 2 * cos.(t * pi) .+ y_i;
      y_geometry = geo.diameter / 2 * sin.(t * pi) .+ z_i;
      
      Plots.plot!(ustrip.(u"mm", x_geometry), ustrip.(u"mm", y_geometry), color=:red)

    elseif typeof(geo) == Rectangle
      # Create rectangle corner points
      # point bottom left
      p_bl = ustrip.(u"mm", [y_i - geo.width / 2, z_i - geo.height / 2]);
      # point upper left
      p_ul = ustrip.(u"mm", [y_i - geo.width / 2, z_i + geo.height / 2]);
      # point upper right
      p_ur = ustrip.(u"mm", [y_i + geo.width / 2, z_i + geo.height / 2]);
      # point bottom right
      p_br = ustrip.(u"mm", [y_i + geo.width / 2, z_i - geo.height / 2]);

      rect = transpose([p_bl p_ul p_ur p_br p_bl])
      Plots.plot!(rect[:,1], rect[:,2], color=:red);
      
    elseif typeof(geo) == Triangle
      # Create triangle corner points
      # point bottom left
      p_bl = ustrip.(u"mm", [y_i - geo.width / 2, z_i - geo.height / 3]);
      # upper point
      p_u = ustrip.(u"mm", [y_i, z_i + 2 / 3 * geo.height]);
      # point bottom right
      p_br = ustrip.(u"mm", [y_i + geo.width / 2, z_i - geo.height / 3]);

      tri = [p_bl p_u p_br p_bl]
      Plots.plot!(tri[1,:], tri[2,:], color=:red, label=nothing);
    end
    
  end
  Plots.display(fig)
end