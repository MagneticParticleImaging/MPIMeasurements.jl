export BidirectionalChannel, take!, put!, inChannel, outChannel, isready, isfull, isopen, eltype

struct BidirectionalChannel{T}
    in::Channel{T}
    out::Channel{T}
end

function BidirectionalChannel{T}(sz::Integer = 0) where {T}
    in = Channel{T}(sz)
    out = Channel{T}(sz)
    return BidirectionalChannel(in, out)
end

function BidirectionalChannel{T}(biChannel::BidirectionalChannel{T}) where {T}
    in = biChannel.out
    out = biChannel.in
    return BidirectionalChannel(in, out)
end

inChannel(biChannel::BidirectionalChannel) = biChannel.in
outChannel(biChannel::BidirectionalChannel) = biChannel.out

take!(biChannel::BidirectionalChannel{T}) where {T} = take!(inChannel(biChannel))
put!(biChannel::BidirectionalChannel{T}, value::T) where {T} = put!(outChannel(biChannel), value)

isready(biChannel::BidirectionalChannel) = isready(inChannel(biChannel))
isfull(biChannel::BidirectionalChannel) = length(outChannel(biChannel).data) >= outChannel(biChannel).sz_max
isopen(biChannel::BidirectionalChannel) = isopen(inChannel(biChannel)) && isopen(outChannel(biChannel))
function close(biChannel::BidirectionalChannel)
    close(biChannel.in)
    close(biChannel.out)
end

eltype(::Type{BidirectionalChannel{T}}) where {T} = T