#####
##### Writing EDFs
#####

#function _write(io::IO, value::T) where T<:Union{PatientID,RecordingID}
#    oldpos = position(io)
#    for f in fieldnames(T)
#        x = getfield(value, f)
#        if ismissing(x)
#            print(io, "X")
#        else
#            print(io, x)
#        end
#        write(io, 0x20)
#    end
#    return position(io) - oldpos  # + 1 ?
#end

_write(io::IO, value) = print(io, value)

function write_padded(io::IO, value, n::Integer)
    b = _write(io, value)
    if b > n
        seek(io, n)  # Truncate by backtracking to the right spot
        b = n
    else
        while b < n
            b += write(io, 0x20)
        end
    end
    return b  # Not really useful, but for consistency with `write`
end

function write_header(io::IO, h::EDFHeader)
    write_padded(io, h.version, 8)
    write_padded(io, h.patient, 80)
    write_padded(io, h.recording, 80)
    write_padded(io, h.continuous ? "EDF+C" : "EDF+D", 44)
end
