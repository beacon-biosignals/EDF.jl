#####
##### Writing EDFs
#####

function write_value(io::IO, value::T) where T<:Union{PatientID,RecordingID}
    nb = 0
    for f in fieldnames(T)
        x = getfield(value, f)
        if T <: RecordingID && f === :startdate
            nb += write_value(io, "Startdate ")
        end
        nb += write_value(io, x) + Base.write(io, 0x20)
    end
    return nb
end

function write_annotations(io::IO, record::DataRecord, max_bytes::Integer)
    bytes_written = 0
    for annotation in record
        bytes_written += write_annotation(io, annotation)
    end
    while bytes_written < max_bytes
        bytes_written += Base.write(io, 0x0)
    end
    bytes_written == max_bytes || error("Number of bytes written does not match the size of the data record")
    return bytes_written
end

write_value(io::IO, value) = Base.write(io, string(value))
write_value(io::IO, date::Date) = Base.write(io, uppercase(Dates.format(date, dateformat"dd-u-yyyy")))
write_value(io::IO, ::Missing) = Base.write(io, "X")
write_value(io::IO, x::AbstractFloat) = Base.write(io, string(isinteger(x) ? trunc(Int, x) : x))

function write_annotation(io::IO, annotation::AbstractAnnotation)
    bytes_written = write_value(io, sign(annotation)) + write_value(io, annotation.offset)
    if has_duration(annotation)
        bytes_written += Base.write(io, 0x15) + write_value(io, annotation.duration)
    end
    bytes_written += Base.write(io, footer(annotation)...)
    if has_events(annotation)
        for event in annotation.events
            bytes_written += Base.write(io, event, 0x14)
        end
    end
    bytes_written += Base.write(io, 0x0)
    return bytes_written
end

function write_annotation(io::IO, annotations::Vector{<:AbstractAnnotation})
    bytes_written = 0
    for annotation in annotations
        bytes_written += write_annotation(io, annotation)
    end
    return bytes_written
end

write_annotation(::IO, ::Nothing) = 0

sign(annotation::AbstractAnnotation) = annotation.offset >= 0 ? '+' : '-'

has_duration(annotation::RecordAnnotation) = false
has_duration(annotation::TimestampAnnotation) = annotation.duration !== nothing

duration(annotation::RecordAnnotation) = missing
duration(annotation::TimestampAnnotation) = annotation.duration

footer(annotation::RecordAnnotation) = (0x14, 0x14)
footer(annotation::TimestampAnnotation) = 0x14

has_events(annotation::RecordAnnotation) = true
has_events(annotation::TimestampAnnotation) = annotation.events !== nothing

function write_padded(io::IO, value, n::Integer)
    b = write_value(io, value)
    @assert b <= n
    while b < n
        b += Base.write(io, 0x20)
    end
    return b
end

function write_file_header(io::IO, header::FileHeader, signal_count::Integer)
    return nothing
end

function write_header(io::IO, file::File)
    h = file.header
    has_anno = file.annotations !== nothing
    signal_count = h.n_signals + has_anno
    b = write_padded(io, h.version, 8) +
        write_padded(io, h.patient, 80) +
        write_padded(io, h.recording, 80) +
        write_padded(io, Dates.format(h.start, dateformat"dd\.mm\.yyHH\.MM\.SS"), 16) +
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
    max_bytes = file.annotations.header.n_samples * 2
    for i in 1:file.header.n_records
        for signal in file.signals
            n = signal.header.n_samples
            s = (i - 1) * n
            stop = min(s + n, length(signal.samples))
            b += Base.write(io, view(signal.samples, s+1:stop))
        end
        if file.annotations !== nothing
            b += write_annotations(io, file.annotations.records[i], max_bytes)
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
