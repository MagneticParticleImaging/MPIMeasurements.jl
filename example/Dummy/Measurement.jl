using MPIMeasurements

scanner = MPIScanner("DummyScanner")

temperatureSensor = getDevice("my_temperature_sensor_id")
@info getTemperature