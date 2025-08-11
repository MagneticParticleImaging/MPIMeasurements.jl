using GLMakie, Observables
using MPIMeasurements, MPIFiles
using Dates, Logging, LoggingExtras

GLMakie.set_theme!(fonts = (;regular="DejaVu Sans Mono", bold="DejaVu Sans Bold"))  # Set default font for all components

mutable struct SimpleProtocolGUI
    fig::Figure
    protocol_name::String
    scanner_name::String
    state::Observable{String}
    progress::Observable{String}
    log_messages::Observable{Vector{String}}
    log_textbox::Textbox
    init_button::Button
    execute_button::Button
    pause_button::Button
    cancel_button::Button
    button_row::Vector{Button} # All current bottom-row buttons (either control or decision)
    decision_active::Observable{Bool}
    decision_buttons::Vector{Button}
    
    function SimpleProtocolGUI(protocol_name::String, scanner_name::String)
        fig = Figure(size = (800, 400), focus_on_show = true)
        state_obs = Observable("UNDEFINED")
        progress_obs = Observable("0/0")
        log_messages_obs = Observable(String[])
        decision_active = Observable(false)
        decision_buttons = Button[]
        
        Label(fig[1, 2:5], "Protocol: $protocol_name | Scanner: $scanner_name", fontsize = 16, font = :bold)
        status_label = Label(fig[2, 2:5], "State: UNDEFINED | Progress: 0/0", fontsize = 14, font = :bold)
        
        tb = Textbox(fig[3, 1:6], placeholder="No messages yet...", displayed_string="No messages yet...", width=Relative(0.95), height=Relative(0.95), restriction=(inputchar -> false), font=:regular)
        width = Observable(tb.layoutobservables.computedbbox[].widths[1])
        visible_log_lines = Observable(1)
        log_scroll_offset = Observable(0)  # 0 = bottom (latest), positive = scroll up
        
        # Control buttons (default)
        init_btn = Button(fig[4, 2], label = "Initialize")
        execute_btn = Button(fig[4, 3], label = "Execute")
        pause_btn = Button(fig[4, 4], label = "Pause")
        cancel_btn = Button(fig[4, 5], label = "Cancel")
        button_row = Any[init_btn, execute_btn, pause_btn, cancel_btn]
        
        gui = new(fig, protocol_name, scanner_name, state_obs, progress_obs, log_messages_obs,
                 tb, init_btn, execute_btn, pause_btn, cancel_btn, button_row, decision_active, decision_buttons)
        
        # Set up reactive updates
        on(state_obs) do state
            status_label.text[] = "State: $state | Progress: $(progress_obs[])"
        end
        on(progress_obs) do progress
            status_label.text[] = "State: $(state_obs[]) | Progress: $progress"
        end
        function setLogText(messages)
            if isempty(messages)
                tb.stored_string = "No messages yet..."
                tb.displayed_string = "No messages yet..."
            else
                # Estimate max chars per line based on textbox width and font size
                font_width_px = 8.6
                max_chars = max(Int(floor(width[] / font_width_px)), 10)

                # Wrap each line manually - Unicode-safe version
                function wrap_line(line, max_chars)
                    wrapped = String[]
                    chars = collect(line)  # Convert to array of characters
                    i = 1
                    while i <= length(chars)
                        end_idx = min(i + max_chars - 1, length(chars))
                        push!(wrapped, join(chars[i:end_idx]))
                        i += max_chars
                    end
                    return wrapped
                end

                wrapped_lines = String[]
                for msg in messages
                    append!(wrapped_lines, wrap_line(msg, max_chars))
                end

                n = visible_log_lines[]
                total = length(wrapped_lines)
                offset = log_scroll_offset[]
                max_offset = max(total - n, 0)
                offset = clamp(offset, 0, max_offset)
                log_scroll_offset[] = offset
                start_idx = max(total - n - offset + 1, 1)
                end_idx = max(total - offset, 1)
                shown = wrapped_lines[start_idx:end_idx]

                tb.stored_string = join(shown, "\n")
                tb.displayed_string = join(shown, "\n")
            end
        end
        # Mouse wheel scroll event for custom scrolling
        on(events(fig.scene).scroll) do scroll_event
            if !(tb.focused[])
                # return
            end

            if length(gui.log_messages[]) > visible_log_lines[]
                log_scroll_offset[] = clamp(log_scroll_offset[] + sign(scroll_event[2]), 0, max(length(gui.log_messages[]) - visible_log_lines[], 0))
                setLogText(gui.log_messages[])
            end
        end
        on(tb.layoutobservables.computedbbox) do bbox
            if bbox.widths[2] > 0
                new_visible_log_lines = max(Int(floor((bbox.widths[2] - 10) / 16.33)), 1)
                if new_visible_log_lines != visible_log_lines[]
                    visible_log_lines[] = new_visible_log_lines
                    setLogText(gui.log_messages[])
                end

                currentWidth = tb.layoutobservables.computedbbox[].widths[1]
                if currentWidth !== width[]
                    width[] = currentWidth
                    setLogText(gui.log_messages[])
                end
            end
        end
        on(log_messages_obs) do messages
            log_scroll_offset[] = 0
            setLogText(messages)
        end
        on(tb.displayed_string) do new_text # Prevent character deletion
            if isnothing(new_text) || isnothing(tb.stored_string[])
                return
            end

            if length(new_text) < length(tb.stored_string[])
                tb.displayed_string[] = tb.stored_string[]
            end
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
    
    gui.log_messages[] = current_messages
end

# Show decision dialog in a separate modal window
function show_decision_dialog!(gui::SimpleProtocolGUI, message::String, choices::Vector{String}, callback::Function, handlerCallback::Function)
    for i in reverse(eachindex(gui.fig.content))
        c = gui.fig.content[i]
        if c isa Button
            delete!(c)
        end
    end
    for (i, btn) in enumerate(gui.button_row)
        col = 1 + i
        Button(gui.fig[4, col], label=btn.label)
    end

    # Mark decision active
    gui.decision_active[] = true
    add_log_message!(gui, "Decision needed: $message")
    add_log_message!(gui, "Choices: $(join(choices, ", "))")

    # Create decision dialog figure
    dialog_fig = Figure(size = (600, 200))

    Label(dialog_fig[1, 1:length(choices)], message, fontsize=14, font=:bold)
    btns = Button[]
    for (i, choice) in enumerate(choices)
        btn = Button(dialog_fig[2, i], label=choice)
        push!(btns, btn)
    end

    # Show dialog window
    dialog_window = display(GLMakie.Screen(title="PNS Studie - Decision Dialog"), dialog_fig)

    on(events(dialog_fig.scene).window_open) do _
        if !isempty(gui.decision_buttons)
            cancel_idx = findfirst(btn -> lowercase(btn.label[]) == "cancel", gui.decision_buttons)
            hide_decision_dialog!(gui, handlerCallback)
            if cancel_idx !== nothing
                callback(cancel_idx)
            end
        end
    end

    # Button click handler
    for (i, btn) in enumerate(btns)
        on(btn.clicks) do _
            hide_decision_dialog!(gui, handlerCallback)
            if dialog_window isa GLMakie.Screen
                GLMakie.close(dialog_window)
            end
            callback(i)
        end
    end

    gui.decision_buttons = btns
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
    GLMakie.activate!(title = "PNS Studie", focus_on_show = true)
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
