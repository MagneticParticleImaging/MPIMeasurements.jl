
function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4}, isBackgroundFrame::Vector{Bool}, mdf::MDFv2InMemory;temperatures::Union{Array{Float32}, Nothing}=nothing, drivefield::Union{Array{ComplexF64}, Nothing}=nothing, applied::Union{Array{ComplexF64}, Nothing}=nothing)
	if !ismissing(studyName(mdf))
		name = studyName(mdf)
	else
		name = "n.a."
	end

	if !isnothing(studyTime(mdf))
		date = studyTime(mdf)
	else
		date = now()
	end

	study = Study(store, name; date=date)

	fillMDFStudy(mdf, study)
	fillMDFExperiment(mdf, study)
	fillMDFScanner(mdf, scanner)
	fillMDFTracer(mdf)

	fillMDFMeasurement(mdf, sequence, data, isBackgroundFrame, temperatures = temperatures, drivefield = drivefield, applied = applied)
	fillMDFAcquisition(mdf, scanner, sequence)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end

function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4}, mdf::MDFv2InMemory; bgdata::Union{Array{Float32,4}, Nothing}=nothing, temperatures::Union{Array{Float32}, Nothing}=nothing, drivefield::Union{Array{ComplexF64}, Nothing}=nothing, applied::Union{Array{ComplexF64}, Nothing}=nothing)
	if !ismissing(studyName(mdf))
		name = studyName(mdf)
	else
		name = "n.a."
	end

	if !isnothing(studyTime(mdf))
		date = studyTime(mdf)
	else
		date = now()
	end

	study = Study(store, name; date=date)

	fillMDFStudy(mdf, study)
	fillMDFExperiment(mdf, study)
	fillMDFScanner(mdf, scanner)
	fillMDFTracer(mdf)

	fillMDFMeasurement(mdf, sequence, data, bgdata, temperatures = temperatures, drivefield = drivefield, applied = applied)
	fillMDFAcquisition(mdf, scanner, sequence)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end



function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4},
														positions::Positions, isBackgroundFrame::Vector{Bool}, mdf::MDFv2InMemory; storeAsSystemMatrix::Bool = false, deltaSampleSize::Union{Vector{typeof(1.0u"m")}, Nothing} = nothing, temperatures::Union{Array{Float32}, Nothing}=nothing, drivefield::Union{Array{ComplexF64}, Nothing}=nothing, applied::Union{Array{ComplexF64}, Nothing}=nothing)

	if storeAsSystemMatrix
		study = MPIFiles.getCalibStudy(store)
	else
		if !ismissing(studyName(mdf))
			name = studyName(mdf)
		else
			name = "n.a."
		end

		if !isnothing(studyTime(mdf))
			date = studyTime(mdf)
		else
			date = now()
		end

		study = Study(store, name; date=date)
	end

	fillMDFStudy(mdf, study)
	fillMDFExperiment(mdf, study)
	fillMDFScanner(mdf, scanner)
	fillMDFTracer(mdf)

	@debug isBackgroundFrame

	fillMDFMeasurement(mdf, sequence, data, isBackgroundFrame, temperatures = temperatures, drivefield = drivefield, applied = applied)
	fillMDFAcquisition(mdf, scanner, sequence)
	fillMDFCalibration(mdf, positions, deltaSampleSize = deltaSampleSize)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end



function fillMDFCalibration(mdf::MDFv2InMemory, positions::GridPositions; deltaSampleSize::Union{Vector{typeof(1.0u"m")}, Nothing} = nothing)

	# /calibration/ subgroup

	if !isnothing(deltaSampleSize)
		deltaSampleSize = Float64.(ustrip.(uconvert.(Unitful.m, deltaSampleSize))) : nothing
	end
	
	subgrid = isa(positions,BreakpointGridPositions) ? positions.grid : positions

	# TODO: THIS NEEDS TO BE DEFINED IN THE MDF! we otherwise cannot store these grids
	isMeanderingGrid = isa(subgrid,MeanderingGridPositions)
	@info "Meandering = $(isMeanderingGrid)"

	fov = Float64.(ustrip.(uconvert.(Unitful.m, fieldOfView(subgrid))))
	fovCenter = Float64.(ustrip.(uconvert.(Unitful.m, fieldOfViewCenter(subgrid))))
	size = shape(subgrid)

	method = "robot"
	offsetFields = nothing
	order = "xyz"
	positions = nothing
	snr = nothing

	mdf.calibration = MDFv2Calibration(;
		deltaSampleSize = deltaSampleSize,
		fieldOfView = fov,
		fieldOfViewCenter = fovCenter,
		method = method,
		offsetFields = offsetFields,
		order = order,
		positions = positions,
		size = size,
		snr = snr,
		isMeanderingGrid = isMeanderingGrid
	)

	return
end
fillMDFCalibration(mdf::MDFv2InMemory, positions::Positions; deltaSampleSize::Union{Vector{typeof(1.0u"m")}, Nothing} = nothing) = @warn  "Storing positions of type $(typeof(positions)) in MDF is not implemented"




function fillMDFScanner(mdf::MDFv2InMemory, scanner::MPIScanner)
	# /scanner/ subgroup
	MPIFiles.scannerBoreSize(mdf, Float64(ustrip(u"m", scannerBoreSize(scanner))))
	MPIFiles.scannerFacility(mdf, scannerFacility(scanner))
	MPIFiles.scannerManufacturer(mdf, scannerManufacturer(scanner))
	MPIFiles.scannerName(mdf, scannerName(scanner))
	MPIFiles.scannerTopology(mdf, scannerTopology(scanner))

	if ismissing(scannerOperator(mdf))
		MPIFiles.scannerOperator(mdf, "default")
	end

	return
end

function fillMDFStudy(mdf::MDFv2InMemory, study::Study)
	# /study/ subgroup
	if ismissing(studyDescription(mdf))
		studyDescription(mdf, "n.a.")
	end

	studyName(mdf, study.name)
	studyNumber(mdf, 0) # FIXME: This is never set!!!!!!
	studyTime(mdf, study.date)
	studyUuid(mdf, study.uuid)

	return
end

function fillMDFExperiment(mdf::MDFv2InMemory, study::Study)
	# /experiment/ subgroup

	expNum = getNewExperimentNum(study)

	if ismissing(experimentDescription(mdf))
		experimentDescription(mdf, "n.a.")
	end

	experimentIsSimulation(mdf, false) # TODO: Should be true with simulated DAQ scanners

	if ismissing(experimentName(mdf))
		experimentName(mdf, "default")
	end

	experimentNumber(mdf, expNum)

	if ismissing(experimentSubject(mdf))
		experimentSubject(mdf, "n.a.")
	end

	experimentUuid(mdf, uuid4())

	return
end

function fillMDFTracer(mdf::MDFv2InMemory)
	# /tracer/ subgroup
	if isnothing(MPIFiles.tracer(mdf))
		MPIFiles.tracer(mdf, defaultMDFv2Tracer())
		addTracer(MPIFiles.tracer(mdf);
							batch = "n.a",
							concentration = 0.0,
							injectionTime = now(),
							name = "n.a",
							solute = "Fe",
							vendor = "n.a.",
							volume = 0.0)
	end

	return
end

function fillMDFMeasurement(mdf::MDFv2InMemory, sequence::Sequence, data::Array{Float32,4},
    bgdata::Nothing; temperatures::Union{Array{Float32}, Nothing}=nothing, drivefield::Union{Array{ComplexF64}, Nothing}=nothing, applied::Union{Array{ComplexF64}, Nothing}=nothing, bgDriveField::Nothing=nothing, bgTransmit::Nothing=nothing)
	numFrames = acqNumFrames(sequence)
	isBackgroundFrame = zeros(Bool, numFrames)
	return fillMDFMeasurement(mdf, sequence, data, isBackgroundFrame, temperatures = temperatures, drivefield = drivefield, applied = applied)
end
function fillMDFMeasurement(mdf::MDFv2InMemory, sequence::Sequence, data::Array{Float32,4},
	bgdata::Union{Array{Float32}}; temperatures::Union{Array{Float32}, Nothing}=nothing, drivefield::Union{Array{ComplexF64}, Nothing}=nothing, applied::Union{Array{ComplexF64}, Nothing}=nothing, bgDriveField::Union{Array{ComplexF64}, Nothing}=nothing, bgTransmit::Union{Array{ComplexF64}, Nothing}=nothing)
	# /measurement/ subgroup
	numFrames = acqNumFrames(sequence)
	numBGFrames = size(bgdata,4)
	data_ = cat(bgdata, data, dims=4)
	drivefield_ = drivefield
	if !isnothing(bgDriveField)
		drivefield_ = cat(bgDriveField, drivefield, dims=4)
	end
	applied_ = applied
	if !isnothing(bgTransmit)
		applied_ = cat(bgTransmit, applied, dims=4)
	end
	isBackgroundFrame = cat(ones(Bool,numBGFrames), zeros(Bool,numFrames), dims=1)
	numFrames = numFrames + numBGFrames
	return fillMDFMeasurement(mdf, sequence, data_, isBackgroundFrame, temperatures = temperatures, drivefield = drivefield_, applied = applied_)
end


function fillMDFMeasurement(mdf::MDFv2InMemory, sequence::Sequence, data::Array{Float32}, isBackgroundFrame::Vector{Bool}; temperatures::Union{Array{Float32}, Nothing}=nothing, drivefield::Union{Array{ComplexF64}, Nothing}=nothing, applied::Union{Array{ComplexF64}, Nothing}=nothing)
	# /measurement/ subgroup
	numFrames = size(data, 4)

	measData(mdf, data)
	measIsBackgroundCorrected(mdf, false)
	measIsBackgroundFrame(mdf, isBackgroundFrame)
	measIsFastFrameAxis(mdf, false)
	measIsFourierTransformed(mdf, false)
	measIsFramePermutation(mdf, false)
	measIsFrequencySelection(mdf, false)
	measIsSparsityTransformed(mdf, false)
	measIsSpectralLeakageCorrected(mdf, false)
	measIsTransferFunctionCorrected(mdf, false)
	if !isnothing(temperature)
		MPIFiles.measTemperatures(mdf, temperatures)
	end
	if !isnothing(drivefield)
		MPIFiles.measObservedDriveField(mdf, drivefield)
	end
	if !isnothing(applied)
		MPIFiles.measAppliedDriveField(mdf, applied)
	end
	return
end


function fillMDFAcquisition(mdf::MDFv2InMemory, scanner::MPIScanner, sequence::Sequence)
	# Needs to be filled after(!) measurement group
	numPeriodsPerFrame_ = acqNumPeriodsPerFrame(sequence)
	numRxChannels_ = rxNumChannels(sequence)
	numSamplingPoints_ = rxNumSamplingPoints(sequence)

	# /acquisition/ subgroup
	#acqGradient(mdf, acqGradient(sequence)) # TODO: Impelent in Sequence
	#MPIFiles.acqGradient(mdf, ustrip.(u"T/m", scannerGradient(scanner)))

	MPIFiles.acqNumAverages(mdf, acqNumAverages(sequence))
	MPIFiles.acqNumFrames(mdf, length(measIsBackgroundFrame(mdf))) # important since we might have added BG frames
	MPIFiles.acqNumPeriodsPerFrame(mdf, acqNumPeriodsPerFrame(sequence))
	offsetField_ = acqOffsetField(sequence)
	MPIFiles.acqOffsetField(mdf, isnothing(offsetField_) || !all(x-> x isa Unitful.MagneticFlux, offsetField_) ? nothing : ustrip.(u"T", offsetField_))
	MPIFiles.acqStartTime(mdf, Dates.unix2datetime(time())) #seqCont.startTime) # TODO as parameter, start time from protocol

	# /acquisition/drivefield/ subgroup
	MPIFiles.dfBaseFrequency(mdf, ustrip(u"Hz", dfBaseFrequency(sequence)))
	MPIFiles.dfCycle(mdf, ustrip(u"s", dfCycle(sequence)))
	MPIFiles.dfDivider(mdf, dfDivider(sequence))
	MPIFiles.dfNumChannels(mdf, dfNumChannels(sequence))
	MPIFiles.dfPhase(mdf, ustrip.(u"rad", dfPhase(sequence)))
	MPIFiles.dfStrength(mdf, ustrip.(u"T", dfStrength(sequence)))
	MPIFiles.dfWaveform(mdf, fromWaveform.(dfWaveform(sequence)))

	# /acquisition/receiver/ subgroup
	MPIFiles.rxBandwidth(mdf, ustrip(u"Hz", rxBandwidth(sequence)))
	convFactor = zeros(2, numRxChannels_)
	convFactor[1, :] .= 1.0
	MPIFiles.rxDataConversionFactor(mdf, convFactor)
	MPIFiles.rxNumChannels(mdf, numRxChannels_)
	MPIFiles.rxNumSamplingPoints(mdf, numSamplingPoints_)
	MPIFiles.rxUnit(mdf, "V")

	# transferFunction
	if hasTransferFunction(scanner)
		numFreq = div(numSamplingPoints_,2)+1
		freq = collect(0:(numFreq-1))./(numFreq-1).*ustrip(u"Hz", rxBandwidth(sequence))
		tf_ =  getTransferFunction(scanner)
		tf = tf_(freq,1:numRxChannels_)
		MPIFiles.rxTransferFunction(mdf, tf)
		MPIFiles.rxInductionFactor(mdf, tf_.inductionFactor)
	end

end
