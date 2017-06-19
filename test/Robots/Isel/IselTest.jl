using MPIMeasurements
using Base.Test
using Unitful

moveRelCmd = moveRel(10.0u"mm", 30, 20.0u"mm", 10000, 30.0u"mm", 40000)
@test moveRelCmd == "@0A 800,30,1600,10000,2400,40000,0,30\r"
