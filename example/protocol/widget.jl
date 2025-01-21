using Term, Term.LiveWidgets

mutable struct ProtocolInformationWidget <: AbstractWidget
  internals::Term.LiveWidgets.WidgetInternals
  controls::AbstractDict
  title::String
  # Logging
  messages::Vector{String}
  attached::Bool
  curr_message::Int
  # Decision
  decision::Union{Nothing, String}
  choices::Union{Nothing, Vector{String}}
  curr_choice::Int
  callback::Union{Nothing, Base.Callable}
end
function ProtocolInformationWidget(messages::Vector{String} = String[]; controls = proto_controls, height = 30, width = Term.console_width(), title = "", 
  on_draw::Union{Nothing,Function} = nothing,
  on_activated::Function = LiveWidgets.on_activated,
  on_deactivated::Function = LiveWidgets.on_deactivated,
)
  internals = LiveWidgets.WidgetInternals(
    Term.Measure(height, width),
    nothing,
    on_draw,
    on_activated,
    on_deactivated,
    false,
  )
  return ProtocolInformationWidget(internals, controls, title, messages, true, length(messages), nothing, nothing, 0, nothing)

end
function Base.push!(widget::ProtocolInformationWidget, str::String)
  push!(widget.messages, str)
  if widget.attached
    widget.curr_message = length(widget.messages)
  end
end
function askQuestion(widget::ProtocolInformationWidget, decision::String, choices::Vector{String}, cb = nothing)
  widget.decision = decision
  widget.choices = choices
  widget.curr_choice = 1
  widget.callback = cb
end

function next_line(widget::ProtocolInformationWidget, ::Char)
  widget.curr_message = min(widget.curr_message  + 1, length(widget.messages))
  widget.attached = widget.curr_message == length(widget.messages)
end
  function prev_line(widget::ProtocolInformationWidget, ::Char)
  widget.curr_message = max(widget.curr_message - 1, 1)
  widget.attached = false
end
attach_top(widget::ProtocolInformationWidget, ::Union{Char, HomeKey}) = widget.attached = true
toend(widget::ProtocolInformationWidget, ::Union{Char, EndKey}) = widget.curr_message = 1

function next_choice(widget::ProtocolInformationWidget, ::Union{Char, ArrowRight})
  if !isnothing(widget.decision)
    widget.curr_choice = min(widget.curr_choice + 1, length(widget.choices))
  end
end
function prev_choice(widget::ProtocolInformationWidget, ::Union{Char, ArrowLeft})
  if !isnothing(widget.decision)
    widget.curr_choice = min(widget.curr_choice - 1, 1)
  end
end
function confirm_choice(widget::ProtocolInformationWidget, ::Enter)
  if !isnothing(widget.decision) && !isnothing(widget.callback)
    widget.callback(widget.curr_choice)
  end
  widget.decision = nothing
  widget.choices = nothing
  widget.curr_choice = 1
  widget.callback = nothing
end

proto_controls = Dict(
  # Logging
  'w' => next_line,
  's' => prev_line,
  HomeKey() => attach_top,
  EndKey() => toend,
  Esc() => LiveWidgets.quit,
  'q' => LiveWidgets.quit,
  # Decisions
  ArrowRight() => next_choice,
  'd' => next_choice,
  ArrowLeft() => prev_choice,
  'a' => prev_choice,
  Enter() => confirm_choice,
)

function LiveWidgets.on_layout_change(widget::ProtocolInformationWidget, m::Term.Measure)
  widget.internals.measure = m
end
function Term.frame(widget::ProtocolInformationWidget)
  isnothing(widget.internals.on_draw) || widget.internals.on_draw(widget)

  if isnothing(widget.decision)
    return frame_messages(widget)
  else
    return frame_decision(widget)
  end
end

function frame_messages(widget::ProtocolInformationWidget)
  measure = widget.internals.measure
  height = measure.h
  width = measure.w
  numlines = max(height - 5, 1)

  # From curr_message down up to numlines messages
  curr = widget.curr_message
  # First get maximum messages, convert to lines and then get numlines from then
  # Adapted from Pager.jl
  messages = join(reverse(widget.messages[max(curr - numlines, 1):curr]))
  reshaped_content = Term.reshape_code_string(messages, width - 6)
  text = split(string(RenderableText(reshaped_content; width = width - 6)), "\n")[max(end-numlines, 1):end]
  text = collect(text)

  style = LiveWidgets.isactive(widget) ? "red" : "blue dim"

  # return content
  return Panel(
      text,
      fit = false,
      width = width,
      height = height,
      padding = (2, 0, 1, 0),
      subtitle = "Message: $(widget.curr_message) of $(length(widget.messages))",
      subtitle_style = "bold dim",
      subtitle_justify = :right,
      style = style,
      title = widget.title,
      title_style = "bold white",
  )
end

function frame_decision(widget::ProtocolInformationWidget)
  measure = widget.internals.measure
  height = measure.h
  width = measure.w

  decisionPanel = Panel(widget.decision, 
    title = "User Input",
    fit = false,
    width = width,
    height = Int(round(0.6 * height)),
    box = :DOUBLE,
    style = "red"
  )

  choicePanels = map(i -> begin
    return Panel(widget.choices[i],
    fit = false,
    width = div(width, length(widget.choices)),
    height = Int(round(0.3 * height)),
    style = i == widget.curr_choice && LiveWidgets.isactive(widget) ? "red" : "white"
    )
  end, 1:length(widget.choices)
  )
  return decisionPanel / Term.Layout.hstack(choicePanels...)
end