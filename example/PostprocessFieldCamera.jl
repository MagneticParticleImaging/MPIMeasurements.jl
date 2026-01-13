# Post-process field camera measurement using student postprocessing
using HDF5, Unitful

# Path to measurement HDF5 file (adjust as needed)
filename = length(ARGS) > 0 ? ARGS[1] : "porridge_field_measurement.h5"

if !isfile(filename)
  println("File not found: $filename")
  exit(1)
end

# Include student postprocessing code (update path if necessary)
sppath = raw"C:/Users/Philip Suskin/Documents/repos/Julia/spericalsensor_ba-janne_hamann/SteuerungPostProcessing/postprocessing.jl"
if isfile(sppath)
  include(sppath)
else
  println("Student postprocessing not found at $sppath")
  exit(1)
end

# Read sensor data: saved as /sensorData (3 x numSensors x numMeasurements) without units
h5open(filename, "r") do f
  dataArray = read(f, "/sensorData")
  timestamps = read(f, "/timestamps")
  numMeasurements = size(dataArray, 3)
  numSensors = size(dataArray, 2)

  # Construct data vector: data[i] is 3 x numSensors matrix with Unitful Tesla
  data = Vector{Matrix{typeof(1.0u"T")}}(undef, numMeasurements)
  for i in 1:numMeasurements
    mat = dataArray[:, :, i] .* 1.0 # ensure Float
    data[i] = (mat .* 1u"T")
  end

  # Prepare sum_sensors array
  sum_sensors = zeros(typeof(1.0u"T"), numMeasurements)

  # Call student's postprocessing(data, sens_vec, sum_sensors)
  sens_vec = 1:numSensors
  t_start, t_k = postprocessing(data, sens_vec, sum_sensors)

  println("Detected t_start = $t_start")
  println("First 10 t_k indices: ", t_k[1:10])
end
