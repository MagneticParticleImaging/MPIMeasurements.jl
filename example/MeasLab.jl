using MPIMeasurements
using Gtk.ShortNames

import Base: getindex
import MPIMeasurements: measurement

type MeasLab
  builder
  daq
  data
  dataBG
  dataBGStore
  params
  cTD
  cFD
  freq
  timePoints
  signalHandler
  mdfstore
  studies
  currStudyName
  currExpNum
  experiments
end

getindex(m::MeasLab, w::AbstractString) = G_.object(m.builder, w)

function MeasLab(filenameConfig=nothing)

  uifile = joinpath(Pkg.dir("MPILib"),"src","UI","builder","measlab.xml")

  if filenameConfig != nothing
    scanner = MPIScanner(filenameConfig)
    daq = getDAQ(scanner)
    mdfstore = MDFDatasetStore( daq["datasetStore"] )
  else
    daq = nothing
    mdfstore = MDFDatasetStore( "/opt/data/MPS1" )
  end

  m = MeasLab( Builder(filename=uifile),
                  daq, nothing, nothing, nothing, nothing, nothing,nothing,
                  nothing, nothing, Dict{Symbol,Any}(), mdfstore, nothing,
                  nothing, nothing, nothing)

  m.cTD = Canvas()
  m.cFD = Canvas()

  push!(m["boxTD"],m.cTD)
  setproperty!(m["boxTD"],:expand,m.cTD,true)

  push!(m["boxFD"],m.cFD)
  setproperty!(m["boxFD"],:expand,m.cFD,true)


  invalidateBG(C_NULL, m)

  Gtk.@sigatom setproperty!(m["lbInfo"],:use_markup,true)


  if m.daq != nothing
    setInfoParams(m)
    setParams(m, m.daq.params)
    Gtk.@sigatom setproperty!(m["entConfig"],:text,filenameConfig)
  else
    Gtk.@sigatom setproperty!(m["tbMeasure"],:sensitive,false)
    Gtk.@sigatom setproperty!(m["tbMeasureBG"],:sensitive,false)
  end

  w = m["measWindow"]
  #G_.transient_for(w, mpilab["mainWindow"])
  #G_.modal(w,true)
  showall(w)

  initCallbacks(m)

  return m
end

function initCallbacks(m)
  signal_connect(measurement, m["tbMeasure"], "clicked", Void, (), false, m )
  signal_connect(measurementBG, m["tbMeasureBG"], "clicked", Void, (), false, m)
  signal_connect(showData, m["adjFrame"], "value_changed", Void, (), false, m )
  signal_connect(showData, m["adjPatch"], "value_changed", Void, (), false, m)
  signal_connect(showData, m["adjRxChan"], "value_changed", Void, (), false, m)
  signal_connect(showData, m["adjMinTP"], "value_changed", Void, (), false, m)
  signal_connect(showData, m["adjMaxTP"], "value_changed", Void, (), false, m)
  signal_connect(showData, m["adjMinFre"], "value_changed", Void, (), false, m)
  signal_connect(showData, m["adjMaxFre"], "value_changed", Void, (), false, m)
  signal_connect(showData, m["cbShowBG"], "toggled", Void, (), false, m)
  signal_connect(showData, m["cbSubtractBG"], "toggled", Void, (), false, m)
  signal_connect(loadExperiment, m["cbCorrTF"], "toggled", Void, (), false, m)

  signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Void, (), false, m)
  signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Void, (), false, m)
  signal_connect(invalidateBG, m["adjNumPeriods"], "value_changed", Void, (), false, m)
  signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Void, (), false, m)

  m.signalHandler[:cbStudyNames] =
      signal_connect(updateExperiments, m["cbStudyNames"], "changed", Void, (), false, m)
  signal_connect(updateExperiments, m["entStudy"], "changed", Void, (), false, m)
  m.signalHandler[:cbExpNum] =
        signal_connect(loadExperiment, m["cbExpNum"], "changed", Void, (), false, m)

  updateStudies(C_NULL, m)
  Gtk.@sigatom setproperty!(m["cbStudyNames"],:active,0)
end

function updateStudies(widgetptr::Ptr, m::MeasLab)
  @Gtk.sigatom println("Updating Studies ...")
  oldStudyName = m.currStudyName
  m.currStudyName = getproperty(m["entStudy"], :text, String)

  @Gtk.sigatom signal_handler_block(m["cbStudyNames"], m.signalHandler[:cbStudyNames])

  if m.studies != nothing && !isempty(m.studies)
    Gtk.@sigatom empty!(m["cbStudyNames"])
  end
  m.studies = getStudies( m.mdfstore )
  for study in m.studies
    Gtk.@sigatom push!(m["cbStudyNames"], study.name)
  end
  @Gtk.sigatom signal_handler_unblock(m["cbStudyNames"], m.signalHandler[:cbStudyNames])
  #Gtk.@sigatom setproperty!(m["cbStudyNames"],:active,0)
  if oldStudyName!= m.currStudyName
    Gtk.@sigatom setproperty!(m["entStudy"], :text, m.currStudyName)
  end
  return nothing
end


function updateExperiments(widgetptr::Ptr, m::MeasLab)
  @Gtk.sigatom println("Updating Experiments ...")
  m.currStudyName = getproperty(m["entStudy"], :text, String)
  m.currExpNum = getproperty(m["cbExpNum"],:active,Int64)

  @Gtk.sigatom signal_handler_block(m["cbExpNum"], m.signalHandler[:cbExpNum])

  if m.studies != nothing && in(m.currStudyName, [ s.name for s in m.studies] )
    path = joinpath( studydir(m.mdfstore), m.currStudyName)
    study = Study(path,m.currStudyName,"","")

    if m.experiments != nothing && !isempty(m.experiments)
      Gtk.@sigatom empty!(m["cbExpNum"])
    end
    m.experiments = getExperiments(m.mdfstore, study)
    for exp in m.experiments
      Gtk.@sigatom push!(m["cbExpNum"], "$(exp.num)")
    end

  end
  @Gtk.sigatom signal_handler_unblock(m["cbExpNum"], m.signalHandler[:cbExpNum])
  @Gtk.sigatom println("Finished Updating Experiments ...")
  return nothing
end



function loadExperiment(widgetptr::Ptr, m::MeasLab)
  @Gtk.sigatom println("Loading Data ...")
  m.currExpNum = getproperty(m["cbExpNum"],:active,Int64)

  if m.experiments != nothing && m.currExpNum >= 0
    f = MPIFile(m.experiments[m.currExpNum+1].path)
    params = MPIFiles.loadMetadata(f)
    params["acqNumFGFrames"] = acqNumFGFrames(f)
    params["acqNumBGFrames"] = acqNumBGFrames(f)
    setParams(m, params)

    #u = MPIFiles.measDataConv(f)[:,:,:,measFGFrameIdx(f)]
    u = getMeasurements(f, false, frames=measFGFrameIdx(f),
                fourierTransform=false, bgCorrection=false,
                 tfCorrection=getproperty(m["cbCorrTF"], :active, Bool))
    #println(size(u))

    m.freq = rxFrequencies(f) ./ 1000
    m.timePoints = rxTimePoints(f) .* 1000

    if acqNumBGFrames(f) > 0
      #m.dataBG = MPIFiles.measDataConv(f)[:,:,:,measBGFrameIdx(f)]
      m.dataBG = getMeasurements(f, false, frames=measBGFrameIdx(f),
            fourierTransform=false, bgCorrection=false,
            tfCorrection=getproperty(m["cbCorrTF"], :active, Bool))

      Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,true)
      Gtk.@sigatom setproperty!(m["lbInfo"],:label,"")
    else
      invalidateBG(C_NULL,m)
    end
    updateData(m, u)
  end
  return nothing
end


function invalidateBG(widgetptr::Ptr, m::MeasLab)
  m.dataBGStore = nothing
  Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,false)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,
        """<span foreground="red" font_weight="bold" size="x-large"> Warning: No Background Measurement Available!</span>""")
  return nothing
end

function reinitDAQ(widgetptr::Ptr, m::MeasLab)
  if m.daq != nothing
    m.daq["acqNumPeriods"] = getproperty(m["adjNumPeriods"], :value, Int64)
    MPIMeasurements.init(m.daq)
    setInfoParams(m)
  end
  return nothing
end

function setInfoParams(m::MeasLab)

  if length(m.daq["dfFreq"]) > 1
    freqStr = "$(join([ " $(round(x,2)) x" for x in m.daq["dfFreq"] ])[2:end-2]) Hz"
  else
    freqStr = "$(round(m.daq["dfFreq"][1],2)) Hz"
  end
  Gtk.@sigatom setproperty!(m["entDFFreq"],:text,freqStr)
  Gtk.@sigatom setproperty!(m["entDFPeriod"],:text,"$(m.daq["dfPeriod"]*1000) ms")
  Gtk.@sigatom setproperty!(m["entFramePeriod"],:text,"$(m.daq["acqFramePeriod"]) s")
end

function showData(widgetptr::Ptr, m::MeasLab)

  if m.data != nothing && !updating[]
    frame = getproperty(m["adjFrame"], :value, Int64)
    chan = getproperty(m["adjRxChan"], :value, Int64)
    patch = getproperty(m["adjPatch"], :value, Int64)
    minTP = getproperty(m["adjMinTP"], :value, Int64)
    maxTP = getproperty(m["adjMaxTP"], :value, Int64)
    minFr = getproperty(m["adjMinFre"], :value, Int64)
    maxFr = getproperty(m["adjMaxFre"], :value, Int64)

    data = vec(m.data[:,chan,patch,frame])
    if m.dataBG != nothing && getproperty(m["cbSubtractBG"], :active, Bool)
      data[:] .-=  vec(mean(m.dataBG[:,chan,patch,:],2))
    end

    p1 = Winston.plot(m.timePoints[minTP:maxTP],data[minTP:maxTP],"b-",linewidth=5)
    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    p2 = Winston.semilogy(m.freq[minFr:maxFr],abs.(rfft(data)[minFr:maxFr]),"b-o", linewidth=5)
    #Winston.ylabel("u / V")
    Winston.xlabel("f / kHz")
    if m.dataBG != nothing && getproperty(m["cbShowBG"], :active, Bool)
      mid = div(size(m.dataBG,4),2)
      #dataBG = vec(m.dataBG[:,chan,patch,1] .- mean(m.dataBG[:,chan,patch,:],2))
      dataBG = vec( mean(m.dataBG[:,chan,patch,:],2))

      Winston.plot(p1,m.timePoints[minTP:maxTP],dataBG[minTP:maxTP],"k--",linewidth=2)
      Winston.plot(p2,m.freq[minFr:maxFr],abs.(rfft(dataBG)[minFr:maxFr]),"k-x",
                   linewidth=2, ylog=true)
    end
    display(m.cTD ,p1)
    display(m.cFD ,p2)

  end
  return nothing
end

function measurement(widgetptr::Ptr, m::MeasLab)
  Gtk.@sigatom  println("Calling measurement")

  params = getParams(m)
  filename = "ll" #MPIMeasurements.measurement(m.daq, m.mdfstore, params,
            #            controlPhase=true, bgdata=m.dataBGStore)
  updateStudies(C_NULL, m)
  updateExperiments(C_NULL, m)

  expNum = parse(Int64,splitext(splitdir(filename)[end])[1])
  idx=find([ e.num for e in m.experiments] .== expNum)[1]

  Gtk.@sigatom setproperty!(m["cbExpNum"],:active,idx-1)
  return nothing
end

function measurementBG(widgetptr::Ptr, m::MeasLab)
  Gtk.@sigatom println("Calling BG measurement")

  params = getParams(m)
  params["acqNumFGFrames"] = params["acqNumBGFrames"]

  u = MPIMeasurements.measurement(m.daq, params, controlPhase=true)
  m.dataBGStore = u
  #updateData(m, u)

  Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,true)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,"")
  return nothing
end


global const updating = Ref{Bool}(false)

function updateData(m::MeasLab, data)
  updating[] = true

  m.data = data

  Gtk.@sigatom setproperty!(m["adjFrame"],:upper,size(data,4))
  Gtk.@sigatom setproperty!(m["adjFrame"],:value,1)
  Gtk.@sigatom setproperty!(m["adjRxChan"],:upper,size(data,2))
  Gtk.@sigatom setproperty!(m["adjRxChan"],:value,1)
  Gtk.@sigatom setproperty!(m["adjPatch"],:upper,size(data,3))
  Gtk.@sigatom setproperty!(m["adjPatch"],:value,1)
  Gtk.@sigatom setproperty!(m["adjMinTP"],:upper,size(data,1))
  Gtk.@sigatom setproperty!(m["adjMinTP"],:value,1)
  Gtk.@sigatom setproperty!(m["adjMaxTP"],:upper,size(data,1))
  Gtk.@sigatom setproperty!(m["adjMaxTP"],:value,size(data,1))
  Gtk.@sigatom setproperty!(m["adjMinFre"],:upper,div(size(data,1),2)+1)
  Gtk.@sigatom setproperty!(m["adjMinFre"],:value,1)
  Gtk.@sigatom setproperty!(m["adjMaxFre"],:upper,div(size(data,1),2)+1)
  Gtk.@sigatom setproperty!(m["adjMaxFre"],:value,div(size(data,1),2)+1)

  updating[] = false
  showData(C_NULL,m)
end


function getParams(m::MeasLab)
  params = copy(m.daq.params)

  params["acqNumAverages"] = getproperty(m["adjNumAverages"], :value, Int64)
  params["acqNumFGFrames"] = getproperty(m["adjNumFGFrames"], :value, Int64)
  params["acqNumBGFrames"] = getproperty(m["adjNumBGFrames"], :value, Int64)
  params["acqNumPeriods"] = getproperty(m["adjNumPeriods"], :value, Int64)
  params["studyName"] = getproperty(m["entStudy"], :text, String)
  params["studyDescription"] = getproperty(m["entExpDescr"], :text, String)
  params["scannerOperator"] = getproperty(m["entOperator"], :text, String)
  params["dfStrength"]=[getproperty(m["adjDFStrength"], :value, Float64)*1e-3] #TODO
  params["tracerName"] = [getproperty(m["entTracerName"], :text, String)]
  params["tracerBatch"] = [getproperty(m["entTracerBatch"], :text, String)]
  params["tracerVendor"] = [getproperty(m["entTracerVendor"], :text, String)]
  params["tracerVolume"] = [getproperty(m["adjTracerVolume"], :value, Float64)]
  params["tracerConcentration"] = [getproperty(m["adjTracerConcentration"], :value, Float64)]
  params["tracerSolute"] = [getproperty(m["entTracerSolute"], :text, String)]

  return params
end

function setParams(m::MeasLab, params)
  Gtk.@sigatom setproperty!(m["adjNumAverages"], :value, params["acqNumAverages"])
  Gtk.@sigatom setproperty!(m["adjNumPeriods"], :value, params["acqNumPeriods"])
  Gtk.@sigatom setproperty!(m["adjNumFGFrames"], :value, params["acqNumFGFrames"])
  Gtk.@sigatom setproperty!(m["adjNumBGFrames"], :value, params["acqNumBGFrames"])
  Gtk.@sigatom setproperty!(m["entStudy"], :text, params["studyName"])
  Gtk.@sigatom setproperty!(m["entExpDescr"], :text, params["studyDescription"] )
  Gtk.@sigatom setproperty!(m["entOperator"], :text, params["scannerOperator"])
  Gtk.@sigatom setproperty!(m["adjDFStrength"], :value, params["dfStrength"][1]*1e3)

  Gtk.@sigatom setproperty!(m["entTracerName"], :text, params["tracerName"][1])
  Gtk.@sigatom setproperty!(m["entTracerBatch"], :text, params["tracerBatch"][1])
  Gtk.@sigatom setproperty!(m["entTracerVendor"], :text, params["tracerVendor"][1])
  Gtk.@sigatom setproperty!(m["adjTracerVolume"], :value, params["tracerVolume"][1])
  Gtk.@sigatom setproperty!(m["adjTracerConcentration"], :value, params["tracerConcentration"][1])
  Gtk.@sigatom setproperty!(m["entTracerSolute"], :text, params["tracerSolute"][1])
end
