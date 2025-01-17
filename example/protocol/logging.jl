using Logging, LoggingExtras, Dates

mutable struct LockableLogger{L <: AbstractLogger} <: AbstractLogger
  logger::L
  args::Vector{Any}
  kwargs::Vector{Any}
  lock::ReentrantLock
  enabled::Bool
end
LockableLogger(logger::AbstractLogger) = LockableLogger(logger, Any[], Any[], ReentrantLock(), true)

Base.lock(logger::LockableLogger) = lock(logger.lock)
Base.unlock(logger::LockableLogger) = unlock(logger.lock)
Base.lock(f::Base.Callable, logger::LockableLogger) = lock(f, logger.lock)

Logging.shouldlog(logger::LockableLogger, args...) = Logging.shouldlog(logger.logger, args...)
Logging.min_enabled_level(logger::LockableLogger) = Logging.min_enabled_level(logger.logger)

function Logging.handle_message(logger::LockableLogger, args...; kwargs...)
  lock(logger) do
    if logger.enabled
      Logging.handle_message(logger.logger, args...; kwargs...)
    else
      push!(logger.args, args)
      push!(logger.kwargs, kwargs)
    end
  end
end
function MPIMeasurements.enable(logger::LockableLogger)
  lock(logger) do
    logger.enabled = true
    while !isempty(logger.args)
      Logging.handle_message(logger.logger, popfirst!(logger.args)...; popfirst!(logger.kwargs)...)
    end
  end 
end
MPIMeasurements.disable(logger::LockableLogger) = lock(() -> logger.enabled = false, logger)

struct ProtocolScriptLogger{L <: AbstractLogger} <: AbstractLogger
  logger::L
  lockedLogger::LockableLogger
  logpath::String
end

Logging.shouldlog(logger::ProtocolScriptLogger, args...) = Logging.shouldlog(logger.logger, args...)
Logging.min_enabled_level(logger::ProtocolScriptLogger) = Logging.min_enabled_level(logger.logger)

Logging.handle_message(logger::ProtocolScriptLogger, args...; kwargs...) = Logging.handle_message(logger.logger, args...; kwargs...)
MPIMeasurements.enable(logger::ProtocolScriptLogger) = enable(logger.lockedLogger)
MPIMeasurements.disable(logger::ProtocolScriptLogger) = disable(logger.lockedLogger)

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

function ProtocolScriptLogger(logpath::String = joinpath(homedir(), ".mpi/Logs"))
  # Console 
  consolelogger = MinLevelLogger(ConsoleLogger(), Logging.Info)
  lockedlogger = LockableLogger(consolelogger)
  
  # Files
  mkpath(logpath)
  filelogger = MinLevelLogger(DatetimeRotatingFileLogger(logpath, raw"\m\p\i\l\a\b-YYYY-mm-dd.\l\o\g"), Logging.Debug)

  # Combine
  logger = datetime_logger(datetimeFormater_logger(TeeLogger(lockedlogger, filelogger)))
  return ProtocolScriptLogger(logger, lockedlogger, logpath)
end