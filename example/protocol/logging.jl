using Logging, LoggingExtras, Dates

mutable struct ProtocolWidgetLogger <: AbstractLogger
  widget::ProtocolInformationWidget
  logbuffer::IOBuffer
  logger::ConsoleLogger
  lock::ReentrantLock
end
function ProtocolWidgetLogger(widget::ProtocolInformationWidget)
  buffer = IOBuffer()
  context = IOContext(buffer, :limit => true, :compact => true)
  logger = ConsoleLogger(context)
  return ProtocolWidgetLogger(widget, buffer, logger, ReentrantLock())
end
Base.lock(logger::ProtocolWidgetLogger) = lock(logger.lock)
Base.unlock(logger::ProtocolWidgetLogger) = unlock(logger.lock)
Base.lock(f::Base.Callable, logger::ProtocolWidgetLogger) = lock(f, logger.lock)

Logging.shouldlog(logger::ProtocolWidgetLogger, args...) = Logging.shouldlog(logger.logger, args...)
Logging.min_enabled_level(logger::ProtocolWidgetLogger) = Logging.min_enabled_level(logger.logger)

function Logging.handle_message(logger::ProtocolWidgetLogger, args...; kwargs...)
  lock(logger) do
    Logging.handle_message(logger.logger, args...; kwargs...)
    str = String(take!(logger.logbuffer))
    push!(logger.widget, str)
  end
end
function Base.empty!(logger::ProtocolWidgetLogger)
  lock(logger) do

  end
end

struct ProtocolScriptLogger{L <: AbstractLogger} <: AbstractLogger
  logger::L
  widgetlogger::ProtocolWidgetLogger
  logpath::String
end

Logging.shouldlog(logger::ProtocolScriptLogger, args...) = Logging.shouldlog(logger.logger, args...)
Logging.min_enabled_level(logger::ProtocolScriptLogger) = Logging.min_enabled_level(logger.logger)

Logging.handle_message(logger::ProtocolScriptLogger, args...; kwargs...) = Logging.handle_message(logger.logger, args...; kwargs...)

const dateTimeFormatter = DateFormat("yyyy-mm-dd HH:MM:SS.sss")

datetime_logger(logger) = TransformerLogger(logger) do log
  merge(log, (; kwargs = (; log.kwargs..., dateTime = now())))
end

datetimeFormater_logger(logger) = TransformerLogger(logger) do log
  dateTime = nothing
  for (key, val) in log.kwargs
    if key === :dateTime
      dateTime = val
    end
  end
  kwargs = [p for p in pairs(log.kwargs) if p[1] != :dateTime]
  merge(log, (; kwargs = kwargs, message = "$(Dates.format(dateTime, dateTimeFormatter)) $(log.message)"))
end

function ProtocolScriptLogger(widget::ProtocolInformationWidget, logpath::String = joinpath(homedir(), ".mpi/Logs"))
  # Console 
  lockedlogger = ProtocolWidgetLogger(widget)
  
  # Files
  mkpath(logpath)
  filelogger = MinLevelLogger(DatetimeRotatingFileLogger(logpath, raw"\m\p\i\l\a\b-YYYY-mm-dd.\l\o\g"), Logging.Debug)

  # Combine
  logger = datetime_logger(datetimeFormater_logger(TeeLogger(lockedlogger, filelogger)))
  return ProtocolScriptLogger(logger, lockedlogger, logpath)
end
