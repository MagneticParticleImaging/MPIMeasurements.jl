
function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4}, mdf::MDFv2InMemory; bgdata::Union{Array{Float32,4}, Nothing}=nothing)
	name = studyName(mdf)
	date = studyDate(mdf)

	study = Study(store, name; date=date)

	fillMDFStudy(mdf, study)
	fillMDFExperiment(mdf, study, params)
	fillMDFScanner(mdf, scanner, params)
	fillMDFTracer(mdf, params)

	fillMDFMeasurement(mdf, sequence, data, bgdata)
	fillMDFAcquisition(mdf, scanner, sequence)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end


function MPIFiles.saveasMDF(store::DatasetStore, scanner::MPIScanner, sequence::Sequence, data::Array{Float32,4},
positions::Positions, isBackgroundFrame::Vector{Bool}, mdf::MDFv2InMemory)

	if params["storeAsSystemMatrix"]
		study = MPIFiles.getCalibStudy(store)
	else
		name = studyName(mdf)
		date = studyDate(mdf)
		study = Study(store, name; date=date)
	end

	fillMDFStudy(mdf, study)
	fillMDFExperiment(mdf, study, params)
	fillMDFScanner(mdf, scanner, params)
	fillMDFTracer(mdf, params)

	@debug isBackgroundFrame

	fillMDFMeasurement(mdf, sequence, data, isBackgroundFrame)
	fillMDFAcquisition(mdf, scanner, sequence)
	fillMDFCalibration(mdf, positions, params)

	filename = getNewExperimentPath(study)

	return saveasMDF(filename, mdf)
end



function fillMDFCalibration(mdf::MDFv2InMemory, positions::Positions, params::Dict)

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



function fillMDFScanner(mdf::MDFv2InMemory, scanner::MPIScanner, params::Dict)
	# /scanner/ subgroup
	mdf.scanner = MDFv2Scanner(
		boreSize = ustrip(u"m", scannerBoreSize(scanner)),
		facility = scannerFacility(scanner),
		manufacturer = scannerManufacturer(scanner),
		name = scannerName(scanner),
		operator = get(params, "scannerOperator", "default"),
		topology = scannerTopology(scanner)
	)
	return
end

function fillMDFStudy(mdf::MDFv2InMemory, study::Study)
	# /study/ subgroup
	mdf.study = MDFv2Study(;
		description = "n.a.",
		name = study.name,
		number = 0, # FIXME: This is never set!!!!!!
		time = study.date,
		uuid = study.uuid
	)
	return
end

function fillMDFExperiment(mdf::MDFv2InMemory, study::Study, params::Dict)
	# /experiment/ subgroup

	expNum = getNewExperimentNum(study)

	mdf.experiment = MDFv2Experiment(;
		description = get(params,"experimentDescription","n.a."),
		isSimulation = false,
		name = get(params,"experimentName","default"),
		number = expNum,
		subject = get(params,"experimentSubject","n.a."),
		uuid = uuid4()
	)
	return
end

function fillMDFTracer(mdf::MDFv2InMemory, params::Dict)
	# /tracer/ subgroup
	mdf.tracer = MDFv2Tracer(;
		batch = get(params,"tracerBatch",["n.a"]),
		concentration = get(params,"tracerConcentration",[0.0]),
		injectionTime = [t for t in get(params,"tracerInjectionTime", [Dates.unix2datetime(time())]) ],
		name = get(params,"tracerName",["n.a"]),
		solute = get(params,"tracerSolute",["Fe"]),
		vendor = get(params,"tracerVendor",["n.a"]),
		volume = get(params,"tracerVolume",[0.0])
	)
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
	numFrames = size(data,4)

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
