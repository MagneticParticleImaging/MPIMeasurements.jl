# Protocols
The purpose of a `Protocol` is to describe and implement a complex measurement procedure that may involve several `Devices` and `Sequences`, for example a robot-based system matrix calibration.

To achieve this, a `Protocol` acts as a running process, that controls all `Devices` of a scanner to perform its respective measurement. During its runtime a `Protocol` can spawn and join further processes, as well as react to user interaction and queries via a communication channel. This channel allows the same `Protocol` to be reused in scripts, console modes or GUIs.

## Tasks and Channels
Before devling into `Protocols`, let's review some necessary basics of [asynchronous programming](https://docs.julialang.org/en/v1/manual/asynchronous-programming/) and [multi-threading](https://docs.julialang.org/en/v1/manual/multi-threading/) in Julia.

Julia provides `Tasks` (also called coroutines, lightweight or green threads). These are expressions or functions grouped as computation, that is executed as a "thread" which can be interrupted and switched out for a different `Task`. If Julia is started with multiple threads, for example with 5:
```cmd
$ julia -t 5
```
then `Tasks` can run in parallel and on different threads. Depending on the Julia version and the way the `Task` was created, they can even migrate between threads.

The following example is a `Task` that prints the current id of the thread it is run on:
```julia-repl
julia> t = Task(() -> println(Threads.threadid()))
Task (runnable) @0x00007f5a378b2f80

julia> schedule(t)
1
```
After a `Task` is created, it needs to be scheduled before it is run. As a convience, the `@async` macro creates and immidiately schedules a `Task`:
```@repl
@async println(Threads.threadid())
1
```
Using the Julia package `ThreadPools` it is also possible to schedule a `Task` on a specific thread:
```julia-repl
julia> @tspawnat 2 println(Threads.threadid())
2
``` 
Once a `Task` is running, it is possible to wait for it to end in a blocking manner:
```julia-repl
julia> t = @async sleep(3); println(Threads.threadid())
julia> wait(t)
```
or a busy-waiting manner: 
```julia-repl
julia> t = @async sleep(3); println(Threads.threadid())
julia> while !istaskdone(t)
          sleep(0.05)
       end
```
If a `Task` threw an error during its runtime, a `Task` waiting on it will propagate the error. To check if a `Task` failed without waiting on it, one can use `Base.istaskfailed` and `current_exceptions`.

Another important concept for `Protocols` are `Channel`. These are waitable first-in-first-out (FIFO) queues which can be used to pass data between `Tasks`:
```@repl
ch = Channel{Int64}(4) # Buffer up to 4 values
put!(ch, 42) # Blocks if full
isopen(ch) # True as long as the channel is open
isready(ch) # True if channel contains values
close(ch)
isopen(ch)
isready(ch)
temp = take!(ch) # Blocks if empty
isready(ch)
temp == 42
```
Multiple `Tasks` can read and write to a `Channel`, however this always goes into the same "direction". `MPIMeasurements.jl` provides a `BidirectionalChannel`, which encapsulates two `Channels`, allowing a `Protocol` to both receive and send data:
```julia-repl
julia> ch = BidirectionalChannel{Int64}(4)
BidirectionalChannel{Int64}(Channel{Int64}(4), Channel{Int64}(4))

julia> ch2 = BidirectionalChannel(ch)
BidirectionalChannel{Int64}(Channel{Int64}(4), Channel{Int64}(4))

julia> put!(ch, 1)
1

julia> take!(ch2)
1

julia> put!(ch2, 2)
2

julia> take!(ch)
2
```
`Tasks` and `BidirectionalChannel` are the main building blocks of `Protocols`.
## Protocol Structure
`Protocols` have a similar structure to `Devices`. Each `Protocol` has a parameter type that inherits from: 
```julia-repl
abstract type ProtocolParams end
```
and must be named like the `Protocol` itself together with an `Params` suffix.

Similarily, each `Protocol` has a number of mandatory fields, that can be added with the provided macro `add_protocol_fields`. These fields contain the `Scanner` used by the `Protocol`, the name and description of the `Protocol`, its `ProtocolParams` and lastly its communication channel and its active main `Task` or process. 

Lastly, a `Protocol` can have any number of internal fields, these must be provided with a default value.
## Protocol Lifecycle
Similar to a `Sequence`, a `Protocol` is constructed from a `Scanners` configuration directory: 
```julia-repl
julia> protocol = Protocol(scanner, "MPIMeasurementProtocol")
```
This only constructs the `Protocol` and assigns it the value stored in its configuration file. One could now programmatically change the parameters of the `Protocol`.
### Init
The next step is to initialize a `Protocol` execution:
```julia-repl
julia> init(protocol)
```
In this step `MPIMeasurements.jl` checks if the `Protocol` was constructed by a `Scanner` that contains all the necessary `Devices` required by the `Protocol`. Furthermore, it calls the `_init` function of the `Protocol`. In this function a `Protocol` implementation should check if all its arguments are sensible and prepare any internal fields it requires for an execution. This step should not start any `Tasks`. 
### Execute
After its execution has been initialized, a `Protocol` can be started with:
```julia-repl
julia> ch = execute(protocol)
BidirectionalChannel{ProtocolEvent}(32)
```
This function checks if the `Protocol` is currently running and if not it starts a new execution. This involves creating a communication channel, which is returned at the end of the function and starting the `Protocols Execution Task` on a provided thread id (default 1). Once the execution `Task` is finished, the communication channel is closed.
### Cleanup
If a `Protocol` produces temporary files, it can implement the `cleanup` function. After successfull `Protocol` execution, a calling Julia component can then invoke `cleanup` and remove any temporary files.
## Protocol Communication
During its execution a `Protocol` can communicate through its communication channel. From a caller perspective, this can be used to query the `Protocol` for its current progress, for its status or measurement data. It can also be used to ask the `Protocol` to pause and resume or to cancel. The `Protocol` itself can ask for things like a user confirmation or a user choice.

This communication however, is something that has to be deliberately implemented in a `Protocol`, though `MPIMeasurements.jl` provides several helper function for this cause. 

A `Protocol` communicates via `ProtocolEvents`. This is an abstract type hierarchy derived from:
```julia
abstract type ProtocolEvent end
```
`MPIMeasurements.jl` already provides a number of `Event` types. Most are designed as query/answer pairs. The follow examples hightlight a few pairs.
### Event Examples
When a `Protocol` is running, it is helpful to know how far it progressed, especially for longer running `Protocol`. For this, the `ProgressEvents` exist. With these a caller can query the `Protocol` how far it is done and can receives an `Event` containing an `X/Y` reply. 
```julia
struct ProgressQueryEvent <: ProtocolEvent end
struct ProgressEvent <: ProtocolEvent
  done::Int
  total::Int
  unit::AbstractString
  query::ProgressQueryEvent
end
```

If a `Protocol` requires input from the user, it has multiple options. If the input is a yes/no question one can use the following:
```julia
struct DecisionEvent <: ProtocolEvent
  message::AbstractString
end
struct AnswerEvent <: ProtocolEvent
  answer::Bool
  question::DecisionEvent
end
```
This requires a caller that is able to reply to `Protocol` queries. `Protocols` that potentially ask for user input possess the `Interactive` trait.

A last important `Event` example concerns the end of a `Protocol`. It is recommended that a `Protocols Task` does not simply end, instead it should notify the caller that it finished. This allows the caller to query for relevant measurement data or request the `Protocol` to save the data to a file. This process is covered by the following `Events`:
```julia
struct FinishedNotificationEvent <: ProtocolEvent end
struct FinishedAckEvent <: ProtocolEvent end
```
Only after receiving an acknowledgement should the protocol finish.
### Event Handling
A common way for `Protocols` to interact with events is the following pattern:
```julia
function measurementStep(protocol::ExampleProtocol)
  step = @tspawnat protocol.scanner.runtime.producerThreadID doStep(protocol)
  while !istaskdone(step)
    handleEvents(protocol)
    sleep(0.05)
  end
end
```
Here, the `Protocol` does not block its own execution task with a measurement step, instead it spawns a dedicated `Task` on a different thread. This leaves the `Protocol` free to react to `Events`. It invokes the provided function `handleEvents`:
```julia
function handleEvents(protocol::Protocol)
  while isready(protocol.biChannel)
    event = take!(protocol.biChannel)
    handleEvent(protocol, event)
  end
end
```
With this function, a `Protocol` only has to write a function like the following to react to an `Event`:
```julia
function handleEvent(protocol::MPIMeasurementProtocol, event::ProgressQueryEvent)
  framesTotal = protocol..numFrames
  framesDone = min(protocol..nextFrame - 1, framesTotal)
  reply = ProgressEvent(framesDone, framesTotal, "Frames", event)
  put!(protocol.biChannel, reply)
end
```
## Implementing New Protocols
The following example implements a `Protocol`, that uses moves a `Robot` to several defined positions and measures the temperature using a `TemperatureSensor` like the one implemented in the `Device` example.

`MPIMeasurements.jl` already provides a family of robot-based `Protocols`. In particular, this already provides an implementation of the `_execute` function, which is further annotated with comments for this example:
```julia
function _execute(protocol::RobotBasedProtocol)
  @info "Start $(typeof(protocol))"
  scanner_ = scanner(protocol)
  robot = getRobot(scanner_)
  if !isReferenced(robot)
    # Any exception thrown in _execute, produces an ExceptionEvent
    throw(IllegalStateException("Robot not referenced! Cannot proceed!"))
  end

  initMeasData(protocol) # This is method needs to be implemented

  finished = false
  notifiedStop = false
  while !finished
    finished = performMovements(protocol)

    # This code block handels pausing and resuming the measurement 
    notifiedStop = false
    # protocol.stopped is set when a StopEvent is received
    while protocol.stopped
      handleEvents(protocol) # Here we react to Events again
      protocol.cancelled && throw(CancelException())
      if !notifiedStop
        # Notify once that we paused
        put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
        notifiedStop = true
      end
      if !protocol.stopped
        # Notify that we resumed
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
      end
      sleep(0.05)
    end
  end

  # Notify the caller that the protocol finished
  put!(protocol.biChannel, FinishedNotificationEvent())
  # Await acknowledgement
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.01)
  end
  @info "Protocol finished."
end
```
The function uses several internal fields, such as `stopped` and `finishedAcknowledged` which are mandatory for robot-based `Protocols`, additionally to the ones mandatory for any `Protocols`.

The robot-based `Protocols` are implement as a multi-threaded process with three distinct steps per robot movement. A `Protocol` can performan an action `before`, `during` and `after` movement

```julia
function performMovement(protocol::RobotBasedProtocol, robot::Robot, pos::ScannerCoords)
  @info "Pre movement"
  preMovement(protocol) # Needs to be implemented

  enable(robot)
  try
    @sync begin 
      @info "During movement"
      moveRobot = @tspawnat protocol.scanner.generalParams.serialThreadID moveAbs(robot, pos)
      duringMovement(protocol, moveRobot) # Needs to be implemented
    end
  catch ex 
    if ex isa CompositeException
      @error "CompositeException while preparing measurement:"
      for e in ex
        @error e
      end
    end
    rethrow(ex)
  end
  disable(robot)
  
  @info "Post movement"
  postMovement(protocol) # Needs to be implemented
end
```