using MPIMeasurements

# define Grid
shp = [3,3,3]
fov = [3.0,3.0,3.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

scanner = MPIScanner("HeadScanner.toml")

data = measurementSystemMatrix(scanner, positions)
