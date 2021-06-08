maximum(abs.(u[4,1,1,:].- mean(u[4,1,1,:],1))) ./ abs.(mean(u[4,1,1,:],1)
mean(u[4,1,1,:],1))
plot(abs(u[4,1,1,:]))#first harmonic

u = getMeasurements(f, false, frames=measFGFrameIdx(f),
                   fourierTransform=true, bgCorrection=true,
                    tfCorrection=false)
