using GLMakie, Observables
using MPIMeasurements, MPIFiles
using Dates, Logging, LoggingExtras

mutable struct SimpleProtocolGUI
    fig::Figure
    protocol_name::String
    scanner_name::String
    state::Observable{String}
    progress::Observable{String}
    log_messages::Observable{Vector{String}}
    init_button::Button
    execute_button::Button
    pause_button::Button
    cancel_button::Button
    button_row::Vector{Button} # All current bottom-row buttons (either control or decision)
    decision_active::Observable{Bool}
    decision_buttons::Vector{Button}
    
    function SimpleProtocolGUI(protocol_name::String, scanner_name::String)
        fig = Figure(size = (800, 400))
        state_obs = Observable("UNDEFINED")
        progress_obs = Observable("0/0")
        log_lines = round(Int, (fig.scene.viewport.val.widths[2] - 148) / 14)
        log_messages_obs = Observable(String[])
        decision_active = Observable(false)
        decision_buttons = Button[]
        
        Label(fig[1, 2:5], "Protocol: $protocol_name | Scanner: $scanner_name", fontsize = 16)
        status_label = Label(fig[2, 2:5], "State: UNDEFINED | Progress: 0/0", fontsize = 14)
        
        # Log area
        ax = Axis(fig[3, 1:6], backgroundcolor = RGBf(0.95, 0.95, 0.95),
            xlabelvisible = false, ylabelvisible = false,
            xgridvisible = false, ygridvisible = false,
            xticksvisible = false, yticksvisible = false,
            xticklabelsvisible = false, yticklabelsvisible = false,
        )
        # hidespines!(ax)
        log_label = Label(fig[3, 1:6], "No messages yet..." * join(["\n" for _ in 1:log_lines]), 
            fontsize = 12, 
            halign = :left, 
            valign = :top, 
            tellwidth = false, 
            justification = :left)
        
        # Control buttons (default)
        init_btn = Button(fig[4, 2], label = "Initialize")
        execute_btn = Button(fig[4, 3], label = "Execute")
        pause_btn = Button(fig[4, 4], label = "Pause")
        cancel_btn = Button(fig[4, 5], label = "Cancel")
        button_row = Any[init_btn, execute_btn, pause_btn, cancel_btn]
        
        gui = new(fig, protocol_name, scanner_name, state_obs, progress_obs, log_messages_obs,
                 init_btn, execute_btn, pause_btn, cancel_btn, button_row, decision_active, decision_buttons)
        
        # Set up reactive updates
        on(state_obs) do state
            status_label.text[] = "State: $state | Progress: $(progress_obs[])"
        end
        on(progress_obs) do progress
            status_label.text[] = "State: $(state_obs[]) | Progress: $progress"
        end
        function setLogText(messages)
            if isempty(messages)
                log_label.text[] = "No messages yet..." * join(["\n" for _ in 1:log_lines])
            else
                n = min(length(messages), log_lines)
                log_label.text[] = join(messages[end-n+1:end], "\n") * join(["\n" for _ in 1:(log_lines - n + 1)])
            end
        end
        on(log_messages_obs) do messages
            setLogText(messages)
        end
        on(gui.fig.scene.viewport) do x
            height = fig.scene.viewport.val.widths[2]
            log_lines = round(Int, (height - 148) / 14)
            setLogText(log_messages_obs[])
        end

        return gui
    end
end

function update_state!(gui::SimpleProtocolGUI, state::String)
    gui.state[] = state
end

function update_progress!(gui::SimpleProtocolGUI, progress::String)
    gui.progress[] = progress
end

function add_log_message!(gui::SimpleProtocolGUI, message::String)
    current_messages = gui.log_messages[]
    timestamp = Dates.format(now(), "HH:MM:SS")
    formatted_message = "[$timestamp] $message"
    push!(current_messages, formatted_message)
    
    # Keep only last 100 messages
    if length(current_messages) > 100
        current_messages = current_messages[end-99:end]
    end
    
    gui.log_messages[] = current_messages
end

function show_decision_dialog!(gui::SimpleProtocolGUI, message::String, choices::Vector{String}, callback::Function, handlerCallback::Function)
    for i in reverse(eachindex(gui.fig.content))
        c = gui.fig.content[i]
        if c isa Button
            delete!(c)
        end
    end

    empty!(gui.decision_buttons)
    gui.decision_active[] = true
    add_log_message!(gui, "Decision needed: $message")
    add_log_message!(gui, "Choices: $(join(choices, ", "))")
    for (i, choice) in enumerate(choices)
        col = 2 + i
        btn = Button(gui.fig[4, col], label = choice)
        on(btn.clicks) do _
            hide_decision_dialog!(gui, handlerCallback)
            callback(i)
        end
        push!(gui.decision_buttons, btn)
    end
end

function hide_decision_dialog!(gui::SimpleProtocolGUI, handlerCallback::Function)
    for i in reverse(eachindex(gui.fig.content))
        c = gui.fig.content[i]
        if c isa Button
            delete!(c)
        end
    end
    for (i, btn) in enumerate(gui.button_row)
        gui.button_row[i] = Button(gui.fig[4, i + 1], label = btn.label)
    end
    handlerCallback()

    empty!(gui.decision_buttons)
    gui.decision_active[] = false
end

function show_gui!(gui::SimpleProtocolGUI)
    GLMakie.activate!(title="PNS Studie")
    display(gui.fig)
end

function close_gui!(gui::SimpleProtocolGUI)
    # Nothing special needed
end

# Simple logger for testing
mutable struct SimpleGUILogger <: AbstractLogger
    gui::SimpleProtocolGUI
    level::LogLevel
end

SimpleGUILogger(gui::SimpleProtocolGUI; loglevel = Logging.Info) = SimpleGUILogger(gui, loglevel)

Logging.shouldlog(logger::SimpleGUILogger, level, args...) = level >= logger.level
Logging.min_enabled_level(logger::SimpleGUILogger) = logger.level

function Logging.handle_message(logger::SimpleGUILogger, level, message, _module, group, id, file, line; kwargs...)
    add_log_message!(logger.gui, string(message))
end

# Simple combined logger
struct SimpleProtocolGUIScriptLogger <: AbstractLogger
    gui_logger::ActiveFilteredLogger{SimpleGUILogger}
    file_logger::SimpleLogger
end

function makie_conversion_filter(log)
    msg = string(log.message)
    if occursin("Passed on ", msg) && occursin("without conversion", msg)
        return false  # filter out
    end
    return true       # keep all other messages
end
function SimpleProtocolGUIScriptLogger(gui::SimpleProtocolGUI; loglevel = Logging.Info, logpath::String = joinpath(homedir(), ".mpi/Logs"))
    gui_logger = SimpleGUILogger(gui; loglevel = loglevel)
    filtered_gui_logger = ActiveFilteredLogger(makie_conversion_filter, gui_logger)
    
    mkpath(logpath)
    io = open(joinpath(logpath, "mpilab-$(Dates.format(now(), "yyyy-mm-dd")).log"), "a")
    file_logger = SimpleLogger(io, Logging.Debug)
    
    return SimpleProtocolGUIScriptLogger(filtered_gui_logger, file_logger)
end

Logging.shouldlog(logger::SimpleProtocolGUIScriptLogger, args...) = true
Logging.min_enabled_level(logger::SimpleProtocolGUIScriptLogger) = Logging.Debug

function Logging.handle_message(logger::SimpleProtocolGUIScriptLogger, args...; kwargs...)
    Logging.handle_message(logger.gui_logger, args...; kwargs...)
    Logging.handle_message(logger.file_logger, args...; kwargs...)
end
