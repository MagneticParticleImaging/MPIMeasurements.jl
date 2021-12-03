module TestingInteractive


# TODO: This is a workaround for CI with GTK since precompilation fails with headless systems
# Remove after https://github.com/JuliaGraphics/Gtk.jl/issues/346 is resolved
if isinteractive()
  @info "is interactive"
  using Gtk
else
  @info "is not interactive"
end

ask() = ask_dialog("Hallo")

end # module

TestingInteractive.ask()