
function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4}, mdf::MDFv2InMemory; bgdata::Union{Array{Float32,4}, Nothing}=nothing)
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

	fillMDFMeasurement(mdf, sequence, data, bgdata)
	fillMDFAcquisition(mdf, scanner, sequence)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end


function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4},
														positions::Positions, isBackgroundFrame::Vector{Bool}, mdf::MDFv2InMemory; storeAsSystemMatrix::Bool = false)

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

	fillMDFMeasurement(mdf, sequence, data, isBackgroundFrame)
	fillMDFAcquisition(mdf, scanner, sequence)
	fillMDFCalibration(mdf, positions)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end



function fillMDFCalibration(mdf::MDFv2InMemory, positions::Positions)

	# /calibration/ subgroup

	deltaSampleSize = haskey(params, "calibDeltaSampleSize") ?
	Float64.(ustrip.(uconvert.(Unitful.m, params["calibDeltaSampleSize"]))) : nothing

	subgrid = isa(positions,BreakpointGridPositions) ? positions.grid : positions

	# TODO: THIS NEEDS TO BE DEFINED IN THE MDF! we otherwise cannot store these grids
	# params["calibIsMeanderingGrid"] = isa(subgrid,MeanderingGridPositions)

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
		snr = snr
	)

	return
end



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
    bgdata::Union{Array{Float32,4}, Nothing})

	# /measurement/ subgroup
	numFrames = acqNumFrames(sequence)

	if isnothing(bgdata)
		isBackgroundFrame = zeros(Bool, numFrames)
		data_ = data
	else
		numBGFrames = size(bgdata,4)
		data_ = cat(bgdata, data, dims=4)
		isBackgroundFrame = cat(ones(Bool,numBGFrames), zeros(Bool,numFrames), dims=1)
		numFrames = numFrames + numBGFrames
	end

	return fillMDFMeasurement(mdf, sequence, data_, isBackgroundFrame)
end


function fillMDFMeasurement(mdf::MDFv2InMemory, sequence::Sequence, data::Array{Float32,4}, isBackgroundFrame::Vector{Bool})
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
	return
end


function fillMDFAcquisition(mdf::MDFv2InMemory, scanner::MPIScanner, sequence::Sequence)
	# Needs to be filled after(!) measurement group
	numPeriodsPerFrame_ = acqNumPeriodsPerFrame(sequence)
	numRxChannels_ = rxNumChannels(sequence)
	numSamplingPoints_ = rxNumSamplingPoints(sequence)

	# /acquisition/ subgroup
	acqGradient(mdf, acqGradient(sequence))
	acqNumAverages(mdf, acqNumAverages(sequence))
	acqNumFrames(mdf, length(measIsBackgroundFrame(mdf))) # important since we might have added BG frames
	acqNumPeriodsPerFrame(mdf, acqNumPeriodsPerFrame(sequence))
	acqOffsetField(mdf, acqOffsetField(sequence))
	acqStartTime(mdf, Dates.unix2datetime(time())) #seqCont.startTime)

	# /acquisition/drivefield/ subgroup
	dfBaseFrequency(mdf, ustrip(u"Hz", dfBaseFrequency(sequence)))
	dfCycle(mdf, ustrip(u"s", dfCycle(sequence)))
	dfDivider(mdf, dfDivider(sequence))
	dfNumChannels(mdf, dfNumChannels(sequence))
	dfPhase(mdf, ustrip.(u"rad", dfPhase(sequence)))
	dfStrength(mdf, ustrip.(u"T", dfStrength(sequence)))
	dfWaveform(mdf, fromWaveform.(dfWaveform(sequence)))

	# /acquisition/receiver/ subgroup
	rxBandwidth(mdf, ustrip(u"Hz", rxBandwidth(sequence)))
	convFactor = zeros(2,numRxChannels_)
	convFactor[1,:] .= 1.0
	rxDataConversionFactor(mdf, convFactor)
	rxNumChannels(mdf, numRxChannels_)
	rxNumSamplingPoints(mdf, numSamplingPoints_)
	rxUnit(mdf, "V")

	# transferFunction
	if hasTransferFunction(scanner)
		numFreq = div(numSamplingPoints_,2)+1
		freq = collect(0:(numFreq-1))./(numFreq-1).*ustrip(u"Hz", rxBandwidth(sequence))
		tf_ =  TransferFunction(scanner)
		tf = tf_[freq,1:numRxChannels_]
		rxTransferFunction(mdf, tf)
		rxInductionFactor(mdf, tf_.inductionFactor)
	end

end