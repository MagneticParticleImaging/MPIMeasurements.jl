using MPIMeasurements

scanner = MPIScanner("MPS.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)
#<<<<<<< HEAD

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[0.02]
params["acqNumAverages"]=1000
params["calibFieldToVolt"]=[19.4]#dfstrength*calibF2V=Uout1Rp
params["calibRefToField"]=[0.01639344262295082]#[0.013242]calibR2F*Uref=Field

measurementCont(daq, params, controlPhase=true)
#=======
params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[0.001]
params["acqNumAverages"]=1000
#iterativ setting of calibFieldToVolt
#start with dfstrength=1 and calibFieldToVolt=0.98
params["calibFieldToVolt"]=[12.91]
params["calibRefToField"]=[0.012195]

#<<<<<<< HEAD
measurementCont(daq, params, controlPhase=false)
=======
#
measurementCont(daq, params, controlPhase=false)
#>>>>>>> 5c0f102c515252749e73e93636483ed0aa25267d
#>>>>>>> 9375e758066b195c64f90ab5757ce438a2fdddd8
=#
