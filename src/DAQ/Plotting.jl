
using GR
export showDAQData
function showDAQData(u)
  u_ = vec(u[:,1,:,1])
  figure()
  #clf()
  subplot(2,1,1)
  plot(u_)
  subplot(2,1,2)
  semilogy(abs.(rfft(u_)))#,"o-b",lw=2)
  sleep(0.1)
end

function showDAQData(daq,u,frame=1)
  u_ = vec(u[:,1,:,frame])
  figure()
  #clf()
  subplot(2,1,1)
  plot(u_)
  subplot(2,1,2)
  uhat = abs.(rfft(u_))
  freq = (0:(length(uhat)-1)) * daq.params.dfBaseFrequency / daq.params.dfDivider[1,1,1]  / 10

  semilogy(freq,uhat)#,"o-b",lw=2)
  sleep(0.1)
end



export showAllDAQData
function showAllDAQData(u, fignum=1)
  D = size(u,2)
  figure()#fignum)
  #clf()
  for d=1:D
    u_ = vec(u[:,d,:,:])
    subplot(2,D,(d-1)*2+ 1)
    plot(u_)
    subplot(2,D,(d-1)*2+ 2)
    semilogy(abs.(rfft(u_)))#,"o-b",lw=2)
  end
  sleep(0.1)
end
