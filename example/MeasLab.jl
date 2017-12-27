@time using MPIMeasurements
@time using Gtk.ShortNames
@time using GtkReactive
ENV["WINSTON_OUTPUT"] = :gtk
@time import Winston

import Base: getindex
import MPIMeasurements: measurement

type MeasLab
  builder
  daq
  generalParams
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
  btnMeasurement
  updatingStudies
  updatingExperiments
  loadingData
end

getindex(m::MeasLab, w::AbstractString) = G_.object(m.builder, w)

function MeasLab(filenameConfig=nothing)
  println("Starting MeasLab")
  uifile = joinpath(Pkg.dir("MPIMeasurements"),"example","measlab.xml")

  if filenameConfig != nothing
    scanner = MPIScanner(filenameConfig)
    daq = getDAQ(scanner)
    generalParams = getGeneralParams(scanner)
    mdfstore = MDFDatasetStore( generalParams["datasetStore"] )
  else
    daq = nothing
    mdfstore = MDFDatasetStore( "/opt/data/MPS1" )
  end

  m = MeasLab( Builder(filename=uifile),
                  daq, generalParams, nothing, nothing, nothing, nothing, nothing,nothing,
                  nothing, nothing, Dict{Symbol,Any}(), mdfstore, nothing,
                  nothing, nothing, nothing, nothing, false, false, false)

  m.btnMeasurement = button(; widget=m["tbMeasure"])

  println("Type constructed")

  m.cTD = Canvas()
  m.cFD = Canvas()

  push!(m["boxTD"],m.cTD)
  setproperty!(m["boxTD"],:expand,m.cTD,true)

  push!(m["boxFD"],m.cFD)
  setproperty!(m["boxFD"],:expand,m.cFD,true)

  println("InvalidateBG")
  invalidateBG(C_NULL, m)

  Gtk.@sigatom setproperty!(m["lbInfo"],:use_markup,true)


  if m.daq != nothing
    setInfoParams(m)
    setParams(m, merge!(m.generalParams,toDict(m.daq.params)))
    Gtk.@sigatom setproperty!(m["entConfig"],:text,filenameConfig)
  else
    Gtk.@sigatom setproperty!(m["tbMeasure"],:sensitive,false)
    Gtk.@sigatom setproperty!(m["tbMeasureBG"],:sensitive,false)
  end

  w = m["measWindow"]
  #G_.transient_for(w, mpilab["mainWindow"])
  #G_.modal(w,true)
  showall(w)

  signal_connect(w, "delete-event") do widget, event
    disconnect(m.daq)
  end

  println("InitCallbacks")

  @time initCallbacks(m)

  println("Finished")

  return m
end

function initCallbacks(m)



  #@time signal_connect(measurement, m["tbMeasure"], "clicked", Void, (), false, m )
  #@time signal_connect(measurementBG, m["tbMeasureBG"], "clicked", Void, (), false, m)

  @time signal_connect(m["tbMeasure"], :clicked) do w
    measurement(C_NULL, m)
  end

  @time signal_connect(m["tbMeasureBG"], :clicked) do w
    measurementBG(C_NULL, m)
  end

  timer = nothing
  @time signal_connect(m["tbContinous"], :toggled) do w
    daq = m.daq
    if getproperty(m["tbContinous"], :active, Bool)
      params = merge!(m.generalParams,getParams(m))
      MPIMeasurements.updateParams!(daq, params)
      startTx(daq)
      MPIMeasurements.controlLoop(daq)

      function update_(::Timer)
        uMeas, uRef = readData(daq, 1, currentFrame(daq))
        #showDAQData(daq,vec(uMeas))
        amplitude, phase = MPIMeasurements.calcFieldFromRef(daq,uRef)
        println("reference amplitude=$amplitude phase=$phase")

        updateData(m, uMeas)
      end
      timer = Timer(update_, 0.0, 0.2)
    else
      close(timer)
      stopTx(daq)
    end
  end

  @time for sl in ["adjFrame", "adjPatch","adjRxChan","adjMinTP","adjMaxTP",
                   "adjMinFre","adjMaxFre"]
    signal_connect(m[sl], "value_changed") do w
      showData(C_NULL, m)
    end
  end

  @time for cb in ["cbShowBG", "cbAverage","cbSubtractBG"]
    signal_connect(m[cb], :toggled) do w
      showData(C_NULL, m)
    end
  end

  signal_connect(m["cbCorrTF"], :toggled) do w
    loadExperiment(C_NULL, m)
  end

  signal_connect(m["cbExpNum"], :changed) do w
    loadExperiment(C_NULL, m)
  end

  #@time signal_connect(showData, m["adjFrame"], "value_changed", Void, (), false, m )
  #@time signal_connect(showData, m["adjPatch"], "value_changed", Void, (), false, m)
  #@time signal_connect(showData, m["adjRxChan"], "value_changed", Void, (), false, m)
  #@time signal_connect(showData, m["adjMinTP"], "value_changed", Void, (), false, m)
  #@time signal_connect(showData, m["adjMaxTP"], "value_changed", Void, (), false, m)
  #@time signal_connect(showData, m["adjMinFre"], "value_changed", Void, (), false, m)
  #@time signal_connect(showData, m["adjMaxFre"], "value_changed", Void, (), false, m)
  #@time signal_connect(showData, m["cbShowBG"], "toggled", Void, (), false, m)
  #@time signal_connect(showData, m["cbAverage"], "toggled", Void, (), false, m)
  #@time signal_connect(showData, m["cbSubtractBG"], "toggled", Void, (), false, m)
  #@time signal_connect(loadExperiment, m["cbCorrTF"], "toggled", Void, (), false, m)

  @time signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Void, (), false, m)
  @time signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Void, (), false, m)
  @time signal_connect(invalidateBG, m["adjNumPeriods"], "value_changed", Void, (), false, m)
  @time signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Void, (), false, m)

  @time m.signalHandler[:cbStudyNames] =
      signal_connect(updateExperiments, m["cbStudyNames"], "changed", Void, (), false, m)
  @time signal_connect(updateExperiments, m["entStudy"], "changed", Void, (), false, m)

  #@time m.signalHandler[:cbExpNum] =
  #      signal_connect(loadExperiment, m["cbExpNum"], "changed", Void, (), false, m)

  @time updateStudies(C_NULL, m)
  @time Gtk.@sigatom setproperty!(m["cbStudyNames"],:active,0)
end

function updateStudies(widgetptr::Ptr, m::MeasLab)
  if !m.updatingStudies
    m.updatingStudies = true
    @Gtk.sigatom println("Updating Studies ...")
    oldStudyName = m.currStudyName
    m.currStudyName = getproperty(m["entStudy"], :text, String)

    #@Gtk.sigatom signal_handler_block(m["cbStudyNames"], m.signalHandler[:cbStudyNames])

    if m.studies != nothing && !isempty(m.studies)
      Gtk.@sigatom empty!(m["cbStudyNames"])
    end
    m.studies = getStudies( m.mdfstore )
    for study in m.studies
      Gtk.@sigatom push!(m["cbStudyNames"], study.name)
    end
    #@Gtk.sigatom signal_handler_unblock(m["cbStudyNames"], m.signalHandler[:cbStudyNames])
    #Gtk.@sigatom setproperty!(m["cbStudyNames"],:active,0)
    if oldStudyName!= m.currStudyName
      Gtk.@sigatom setproperty!(m["entStudy"], :text, m.currStudyName)
    end
    m.updatingStudies = false
  end
  return nothing
end


function updateExperiments(widgetptr::Ptr, m::MeasLab)
  if !m.updatingExperiments && !m.updatingStudies
    m.updatingExperiments = true
    @Gtk.sigatom println("Updating Experiments ...")
    m.currStudyName = getproperty(m["entStudy"], :text, String)
    m.currExpNum = getproperty(m["cbExpNum"],:active,Int64)

    #@Gtk.sigatom signal_handler_block(m["cbExpNum"], m.signalHandler[:cbExpNum])

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
    #@Gtk.sigatom signal_handler_unblock(m["cbExpNum"], m.signalHandler[:cbExpNum])
    @Gtk.sigatom println("Finished Updating Experiments ...")
    m.updatingExperiments = false
  end
  return nothing
end



function loadExperiment(widgetptr::Ptr, m::MeasLab)
  if !m.loadingData && !m.updatingExperiments && !m.updatingStudies
    m.loadingData = true
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

        #Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,true)
        #Gtk.@sigatom setproperty!(m["lbInfo"],:label,"")
      else
        invalidateBG(C_NULL,m)
      end
      updateData(m, u)
    end
    m.loadingData = false
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
    m.daq.params.acqNumPeriodsPerFrame = getproperty(m["adjNumPeriods"], :value, Int64)
    reinit(m.daq)
    setInfoParams(m)
  end
  return nothing
end

function setInfoParams(m::MeasLab)

  if length(m.daq.params.dfFreq) > 1
    freqStr = "$(join([ " $(round(x,2)) x" for x in m.daq.params.dfFreq ])[2:end-2]) Hz"
  else
    freqStr = "$(round(m.daq.params.dfFreq[1],2)) Hz"
  end
  Gtk.@sigatom setproperty!(m["entDFFreq"],:text,freqStr)
  Gtk.@sigatom setproperty!(m["entDFPeriod"],:text,"$(m.daq.params.dfPeriod*1000) ms")
  Gtk.@sigatom setproperty!(m["entFramePeriod"],:text,"$(m.daq.params.acqFramePeriod) s")
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

    if getproperty(m["cbAverage"], :active, Bool)
      data = vec(mean(m.data,4)[:,chan,patch,1])
    else
      data = vec(m.data[:,chan,patch,frame])
    end
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

  params = merge!(m.generalParams,getParams(m))
  params["acqNumFrames"] = params["acqNumFGFrames"]

  filename = MPIMeasurements.measurement(m.daq, params, m.mdfstore,
                        controlPhase=true, bgdata=m.dataBGStore)

  updateStudies(C_NULL, m)
  updateExperiments(C_NULL, m)

  expNum = parse(Int64,splitext(splitdir(filename)[end])[1])
  idx=find([ e.num for e in m.experiments] .== expNum)[1]

  Gtk.@sigatom setproperty!(m["cbExpNum"],:active,idx-1)
  return nothing
end

function measurementBG(widgetptr::Ptr, m::MeasLab)
  Gtk.@sigatom println("Calling BG measurement")

  params = merge!(m.generalParams,getParams(m))
  params["acqNumFrames"] = params["acqNumBGFrames"]

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
  params = toDict(m.daq.params)

  params["acqNumAverages"] = getproperty(m["adjNumAverages"], :value, Int64)
  params["acqNumFGFrames"] = getproperty(m["adjNumFGFrames"], :value, Int64)
  params["acqNumBGFrames"] = getproperty(m["adjNumBGFrames"], :value, Int64)
  params["acqNumPeriodsPerFrame"] = getproperty(m["adjNumPeriods"], :value, Int64)
  params["studyName"] = getproperty(m["entStudy"], :text, String)
  params["studyDescription"] = getproperty(m["entExpDescr"], :text, String)
  params["scannerOperator"] = getproperty(m["entOperator"], :text, String)
  params["tracerName"] = [getproperty(m["entTracerName"], :text, String)]
  params["tracerBatch"] = [getproperty(m["entTracerBatch"], :text, String)]
  params["tracerVendor"] = [getproperty(m["entTracerVendor"], :text, String)]
  params["tracerVolume"] = [getproperty(m["adjTracerVolume"], :value, Float64)]
  params["tracerConcentration"] = [getproperty(m["adjTracerConcentration"], :value, Float64)]
  params["tracerSolute"] = [getproperty(m["entTracerSolute"], :text, String)]

  dfString = getproperty(m["entDFStrength"], :text, String)
  params["dfStrength"] = parse.(Float64,split(dfString," x "))*1e-3
  println("DF strength = $(params["dfStrength"])")


  return params
end

function setParams(m::MeasLab, params)
  Gtk.@sigatom setproperty!(m["adjNumAverages"], :value, params["acqNumAverages"])
  Gtk.@sigatom setproperty!(m["adjNumPeriods"], :value, params["acqNumPeriodsPerFrame"])
  Gtk.@sigatom setproperty!(m["adjNumFGFrames"], :value, params["acqNumFrames"])
  Gtk.@sigatom setproperty!(m["adjNumBGFrames"], :value, params["acqNumFrames"])
  Gtk.@sigatom setproperty!(m["entStudy"], :text, params["studyName"])
  Gtk.@sigatom setproperty!(m["entExpDescr"], :text, params["studyDescription"] )
  Gtk.@sigatom setproperty!(m["entOperator"], :text, params["scannerOperator"])
  dfString = *([ string(x*1e3," x ") for x in params["dfStrength"] ]...)[1:end-3]
  Gtk.@sigatom setproperty!(m["entDFStrength"], :text, dfString)

  Gtk.@sigatom setproperty!(m["entTracerName"], :text, params["tracerName"][1])
  Gtk.@sigatom setproperty!(m["entTracerBatch"], :text, params["tracerBatch"][1])
  Gtk.@sigatom setproperty!(m["entTracerVendor"], :text, params["tracerVendor"][1])
  Gtk.@sigatom setproperty!(m["adjTracerVolume"], :value, params["tracerVolume"][1])
  Gtk.@sigatom setproperty!(m["adjTracerConcentration"], :value, params["tracerConcentration"][1])
  Gtk.@sigatom setproperty!(m["entTracerSolute"], :text, params["tracerSolute"][1])
end

#@time @profile m = MeasLab("MPS.toml")
@time @profile m = MeasLab("HeadScanner.toml")
