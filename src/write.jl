#####
##### Writing EDFs
#####

function _write(io::IO, value::T) where T<:Union{PatientID,RecordingID}
    nb = 0
    for f in fieldnames(T)
        x = getfield(value, f)
        if T <: RecordingID && f === :startdate
            nb += _write(io, "Startdate ")
        end
        nb += _write(io, x) + write(io, 0x20)
    end
    return nb
end

_write(io::IO, value) = write(io, string(value))
_write(io::IO, date::Date) = write(io, uppercase(Dates.format(date, dateformat"dd-u-yyyy")))
_write(io::IO, ::Missing) = write(io, "X")
_write(io::IO, x::AbstractFloat) = write(io, string(isinteger(x) ? trunc(Int, x) : x))

function write_padded(io::IO, value, n::Integer)
    b = _write(io, value)
    @assert b <= n
    while b < n
        b += write(io, 0x20)
    end
    return b
end

function write_header(io::IO, file::EDFFile)
    h = file.header
    b = write_padded(io, h.version, 8) +
        write_padded(io, h.patient, 80) +
        write_padded(io, h.recording, 80) +
        _write(io, Dates.format(h.start, dateformat"dd\.mm\.yyHH\.MM\.SS")) +
        write_padded(io, h.nb_header, 8) +
        write_padded(io, h.continuous ? "EDF+C" : "EDF+D", 44) +
        write_padded(io, h.n_records, 8) +
        write_padded(io, h.duration, 8) +
        write_padded(io, h.n_signals, 4)
    for (i, w) in zip(1:fieldcount(Signal)-1, [16, 80, 8, 8, 8, 8, 8, 80, 8])
        for s in file.signals
            b += write_padded(io, getfield(s, i), w)
        end
    end
    ns = 32 * length(file.signals)
    for _ = 1:ns
        b += write(io, 0x20)
    end
    return b
end
