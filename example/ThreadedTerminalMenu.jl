using ThreadPools
import REPL
import REPL: LineEdit, REPLCompletions
import REPL: TerminalMenus

lk = ReentrantLock()

function requestAtREPL()
  lock(lk) do
    @info "Thread started"
    options = ["Yes", "No"]
    menu = TerminalMenus.RadioMenu(options, pagesize=2)
    choice = TerminalMenus.request("Question:", menu)

    if choice == -1
      @info "Cancelled"
    else
      @info "The answer is `$(options[choice])`."
    end
  end
end

@tspawnat 1 requestAtREPL()

@info "Just some arbitrary output"
sleep(1.0)
@info "Just some other arbitrary output"