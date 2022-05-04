export Waveform, WAVEFORM_SINE, WAVEFORM_SQUARE, WAVEFORM_TRIANGLE, WAVEFORM_SAWTOOTH_RISING,
WAVEFORM_SAWTOOTH_FALLING, toWaveform, fromWaveform

"Enum describing the existing waveforms."
@enum Waveform begin
  WAVEFORM_SINE
  WAVEFORM_SQUARE
  WAVEFORM_TRIANGLE
  WAVEFORM_SAWTOOTH_RISING
  WAVEFORM_SAWTOOTH_FALLING
end

waveformRelations = Dict{String, Waveform}(
  "sine" => WAVEFORM_SINE,
  "square" => WAVEFORM_SQUARE,
  "triangle" => WAVEFORM_TRIANGLE,
  "sawtooth_rising" => WAVEFORM_SAWTOOTH_RISING,
  "sawtooth" => WAVEFORM_SAWTOOTH_RISING, # Alias
  "sawtooth_falling" => WAVEFORM_SAWTOOTH_FALLING,
)

toWaveform(value::AbstractString) = waveformRelations[value]
fromWaveform(value::Waveform) = [k for (k, v) in waveformRelations if v == value][1]

function value(w::Waveform, arg_)
  arg = mod(arg_, 1)
  if w == WAVEFORM_SINE
    return sin(2*pi*arg)
  elseif w == WAVEFORM_SQUARE
    return arg < 0.5 ? 1.0 : -1.0
  elseif w == WAVEFORM_TRIANGLE
    if arg < 1/4
      return 4*arg
    elseif arg < 3/4
      return 2-4*arg
    else
      return -4+4*arg
    end
  else
    error("waveform $(w) not supported!")
  end
end