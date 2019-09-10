#####
##### Writing EDFs
#####

function _write(io::IO, value::T) where T<:Union{PatientID,RecordingID}
    nb = 0
    for f in fieldnames(T)
        x = getfield(value, f)
        if ismissing(x)
            nb += write(io, "X")
        else
            nb += write(io, x)
        end
        nb += write(io, 0x20)
    end
    return nb
end

_write(io::IO, value) = write(io, value)

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
    return b
end

function write_header(io::IO, h::EDFHeader)
    n_bytes_written =
        write_padded(io, h.version, 8) +
        write_padded(io, h.patient, 80) +
        write_padded(io, h.recording, 80) +
        write_padded(io, Dates.format(h.start, dateformat"dd\.mm\.yyHH\.MM\.SS"), 16) +
        write_padded(io, h.nb_header, 8) +
        write_padded(io, h.continuous ? "EDF+C" : "EDF+D", 44)
end
