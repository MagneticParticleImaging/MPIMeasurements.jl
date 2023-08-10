try
  while !controlPhaseDone && i <= txCont.params.maxControlSteps
    @info "CONTROL STEP $i"
    startTx(daq)
    # Wait Start
    done = false
    while !done
      done = rampUpDone(daq.rpc)
    end
    @warn "Ramping status" rampingStatus(daq.rpc)
    
    sleep(txCont.params.controlPause)

    @info "Read periods"
    period = currentPeriod(daq)
    uMeas, uRef = readDataPeriods(daq, 1, period + 1, acqNumAverages(seq))
    for ch in daq.rampingChannel
      enableRampDown!(daq.rpc, ch, true)
    end
    
    # Translate uRef/channelIdx(daq) to order as it is used here
    mapping = Dict( b => a for (a,b) in enumerate(channelIdx(daq, daq.refChanIDs)))
    controlOrderChannelIndices = [channelIdx(daq, ch.daqChannel.feedback.channelID) for ch in txCont.controlledChannels]
    controlOrderRefIndices = [mapping[x] for x in controlOrderChannelIndices]
    sortedRef = uRef[:, controlOrderRefIndices, :]
    @info "Performing control step"
    controlPhaseDone = doControlStep(txCont, seq, sortedRef, Ω)
    ####################
    function doControlStep(txCont::TxDAQController, seq::Sequence, uRef, Ω::Matrix)

      Γ = calcFieldFromRef(txCont,seq, uRef)
      ##################
      function calcFieldFromRef(txCont::TxDAQController, seq::Sequence, uRef)
        len = length(txCont.controlledChannels)
        Γ = zeros(ComplexF64, len, len)
      
        for d=1:len
          for e=1:len
            c = ustrip(u"T/V", txCont.controlledChannels[d].daqChannel.feedback.calibration)
      
            uVolt = float(uRef[1:rxNumSamplingPoints(seq),d,1])
      
            a = 2*sum(uVolt.*txCont.cosLUT[:,e])
            b = 2*sum(uVolt.*txCont.sinLUT[:,e])
            @show sqrt(a^2 + b^2)
      
            Γ[d,e] = c*(b+im*a)
          end
        end
        return Γ
      end
      ##################

      daq = dependency(txCont, AbstractDAQ)
    
      @info "reference Γ=" Γ
    
      if controlStepSuccessful(Γ, Ω, txCont)
        ################
        function controlStepSuccessful(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)

          if txCont.params.correctCrossCoupling
            diff = Ω - Γ
          else
            diff = diagm(diag(Ω)) - diagm(diag(Γ))
          end
          deviation = maximum(abs.(diff)) / maximum(abs.(Ω))
          @info "Ω = " Ω
          @info "Γ = " Γ
          @info "Ω - Γ = " diff
          @info "deviation = $(deviation)   allowed= $(txCont.params.amplitudeAccuracy)"
          return deviation < txCont.params.amplitudeAccuracy
        end
        ################

        @info "Could control"
        return true
      else
        newTx = newDFValues(Γ, Ω, txCont)
        ################
        function newDFValues(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)

          κ = txCont.currTx
          if txCont.params.correctCrossCoupling
            β = Γ*inv(κ)
          else 
            @show size(Γ), size(κ)
            β = diagm(diag(Γ))*inv(diagm(diag(κ))) 
          end
          newTx = inv(β)*Ω
        
          @warn "here are the values"
          @show κ
          @show Γ
          @show Ω
          
        
          return newTx
        end
        ################

        oldTx = txCont.currTx
        @info "oldTx=" oldTx 
        @info "newTx=" newTx
    
        if checkDFValues(newTx, oldTx, Γ,txCont)
          ##############
          function checkDFValues(newTx, oldTx, Γ, txCont::TxDAQController)

            calibFieldToVoltEstimate = [ustrip(u"V/T", ch.daqChannel.calibration) for ch in txCont.controlledChannels]
            calibFieldToVoltMeasured = abs.(diag(oldTx) ./ diag(Γ))
          
            @info "" calibFieldToVoltEstimate[1] calibFieldToVoltMeasured[1]
          
            deviation = abs.(1.0 .- calibFieldToVoltMeasured./calibFieldToVoltEstimate)
          
            @info "We expected $(calibFieldToVoltEstimate) and got $(calibFieldToVoltMeasured), deviation: $deviation"
          
            return all( abs.(newTx) .<  ustrip.(u"V", [channel.daqChannel.limitPeak for channel in txCont.controlledChannels]) ) && maximum( deviation ) < 0.2
          end
          ##############

          txCont.currTx[:] = newTx
          setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
        else
          @warn "New values are above voltage limits or are different than expected!"
        end
    
        @info "Could not control !"
        return false
      end
    end
    ####################

    # Wait End
    @info "Waiting for end."
    done = false
    while !done
      done = rampDownDone(daq.rpc)
    end
    masterTrigger!(daq.rpc, false)
    # These reset the amplitude, phase and ramping, so we only reset trigger here
    #stopTx(daq) 
    #setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
    
    i += 1
  end
catch ex
  @error "Exception during control loop"
  @error ex
finally
  
end