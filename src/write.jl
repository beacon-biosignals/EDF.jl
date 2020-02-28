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
        nb += _write(io, x) + Base.write(io, 0x20)
    end
    return nb
end

function write_annotations(io::IO, annotations::AnnotationList, index::Integer)
    (record, timestamp_annotations) = annotations.records[index]
    nb = _write(io, record)
    if timestamp_annotations !== nothing
        for annotation in timestamp_annotations
            nb += _write(io, annotation)
        end
    end
    while nb < annotations.header.n_samples * 2
        nb += Base.write(io, 0x0)
    end
    @assert nb == annotations.header.n_samples * 2
    return nb
end

_write(io::IO, value) = Base.write(io, string(value))
_write(io::IO, date::Date) = Base.write(io, uppercase(Dates.format(date, dateformat"dd-u-yyyy")))
_write(io::IO, ::Missing) = Base.write(io, "X")
_write(io::IO, x::AbstractFloat) = Base.write(io, string(isinteger(x) ? trunc(Int, x) : x))

function _write(io::IO, tal::TimestampAnnotation)
    nb = _write(io, tal.offset >= 0 ? '+' : '-') + _write(io, tal.offset)
    if tal.duration !== nothing
        nb += Base.write(io, 0x15) + _write(io, tal.duration)
    end
    nb += Base.write(io, 0x14)
    mark = position(io)
    join(io, tal.events, '\x14')
    nb += position(io) - mark
    nb += Base.write(io, 0x14, 0x0)
    return nb
end

function _write(io::IO, anno::RecordAnnotation)
    nb = _write(io, anno.offset >= 0 ? '+' : '-') +
         _write(io, anno.offset) +
         Base.write(io, 0x14, 0x14)
    mark = position(io)
    join(io, anno.events, '\x14')
    nb += position(io) - mark
    nb += Base.write(io, 0x0)
    return nb
end

function write_padded(io::IO, value, n::Integer)
    b = _write(io, value)
    @assert b <= n
    while b < n
        b += Base.write(io, 0x20)
    end
    return b
end

function write_header(io::IO, file::File)
    h = file.header
    has_anno = file.annotations !== nothing
    signal_count = h.n_signals + has_anno
    b = write_padded(io, h.version, 8) +
        write_padded(io, h.patient, 80) +
        write_padded(io, h.recording, 80) +
        _write(io, Dates.format(h.start, dateformat"dd\.mm\.yyHH\.MM\.SS")) +
        write_padded(io, 256 * (signal_count + 1), 8) +
        write_padded(io, h.continuous ? "EDF+C" : "EDF+D", 44) +
        write_padded(io, h.n_records, 8) +
        write_padded(io, h.duration, 8) +
        write_padded(io, signal_count, 4)
    pads = [16, 80, 8, 8, 8, 8, 8, 80, 8]
    for (i, w) in zip(1:fieldcount(SignalHeader), pads)
        for s in file.signals
            h = s.header
            b += write_padded(io, getfield(h, i), w)
        end
        if has_anno
            h = file.annotations.header
            b += write_padded(io, getfield(h, i), w)
        end
    end
    ns = 32 * (length(file.signals) + has_anno)
    for _ = 1:ns
        b += Base.write(io, 0x20)
    end
    return b
end

function write_data(io::IO, file::File)
    b = 0
    for i = 1:file.header.n_records
        for signal in file.signals
            n = signal.header.n_samples
            s = (i - 1) * n
            stop = min(s + n, length(signal.samples))
            b += Base.write(io, view(signal.samples, s+1:stop))
        end
        if file.annotations !== nothing
            b += write_annotations(io, file.annotations, i)
        end
    end
    return b
end

"""
    EDF.write(io::IO, edf::EDF.File)
    EDF.write(path::AbstractString, edf::EDF.File)

Write the given `EDF.File` object to the given stream or file and return the number of
bytes written.
"""
write(io::IO, file::File) = write_header(io, file) + write_data(io, file)
write(path::AbstractString, edf::File) = open(io->write(io, edf), path, "w")
