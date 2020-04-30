#####
##### Writing EDFs
#####

#####
##### `write_bytes`
#####

write_bytes(io::IO, value) = Base.write(io, string(value))
write_bytes(io::IO, date::Date) = Base.write(io, uppercase(Dates.format(date, dateformat"dd-u-yyyy")))
write_bytes(io::IO, date::DateTime) = Base.write(io, Dates.format(date, dateformat"dd\.mm\.yyHH\.MM\.SS"))
write_bytes(io::IO, ::Missing) = Base.write(io, "X")
write_bytes(io::IO, x::AbstractFloat) = Base.write(io, string(isinteger(x) ? trunc(Int, x) : x))
write_bytes(io::IO, continuous::Bool) = Base.write(io, continuous ? "EDF+C" : "EDF+D")
write_bytes(::IO, ::Nothing) = 0

function write_bytes(io::IO, metadata::T) where T<:Union{PatientID,RecordingID}
    bytes_written = 0
    for name in fieldnames(T)
        field = getfield(metadata, name)
        if T <: RecordingID && name === :startdate
            bytes_written += write_bytes(io, "Startdate ")
        end
        bytes_written += write_bytes(io, field) + Base.write(io, 0x20)
    end
    return bytes_written
end

function write_bytes(io::IO, annotations::T) where {T<:Union{DataRecord, Vector{<:AbstractAnnotation}}}
    bytes_written = 0
    for annotation in annotations
        bytes_written += write_bytes(io, annotation)
    end
    return bytes_written
end

function write_bytes(io::IO, annotation::AbstractAnnotation)
    bytes_written = Base.write(io, sign(annotation)) +
                    write_bytes(io, annotation.offset)
    if has_duration(annotation)
        bytes_written += Base.write(io, 0x15) +
                         write_bytes(io, duration(annotation))
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

sign(annotation::AbstractAnnotation) = annotation.offset >= 0 ? '+' : '-'

has_duration(annotation::RecordAnnotation) = false
has_duration(annotation::TimestampAnnotation) = annotation.duration !== nothing

duration(annotation::RecordAnnotation) = nothing
duration(annotation::TimestampAnnotation) = annotation.duration

footer(annotation::RecordAnnotation) = (0x14, 0x14)
footer(annotation::TimestampAnnotation) = 0x14

has_events(annotation::RecordAnnotation) = annotation.events !== nothing
has_events(annotation::TimestampAnnotation) = true

function write_padded(io::IO, value, byte_limit::Integer; pad::UInt8=0x20)
    bytes_written = write_bytes(io, value)
    bytes_written <= byte_limit || error("Written value $value contains more bytes than limit $byte_limit")
    while bytes_written < byte_limit
        bytes_written += Base.write(io, pad)
    end
    return bytes_written
end

function write_header(io::IO, file::File)
    has_annotations = file.annotations !== nothing
    signal_count = length(file.signals) + has_annotations
    bytes_written = write_file_header(io, file.header, signal_count) +
                    write_signal_headers(io, file, has_annotations)
    reserved_bytes = 32 * signal_count
    bytes_written += write_padded(io, 0x20, reserved_bytes)
    return bytes_written
end

function write_file_header(io::IO, header::FileHeader, signal_count::Integer)
    total_header_bytes = 256 * (signal_count + 1)
    return write_padded(io, header.version, 8) +
           write_padded(io, header.patient, 80) +
           write_padded(io, header.recording, 80) +
           write_padded(io, header.start, 16) +
           write_padded(io, total_header_bytes, 8) +
           write_padded(io, header.continuous, 44) +
           write_padded(io, header.n_records, 8) +
           write_padded(io, header.duration, 8) +
           write_padded(io, signal_count, 4)
end

function write_signal_headers(io::IO, file::File, has_annotations::Bool)
    bytes_written = 0
    for (field, padding) in zip(1:fieldcount(Signal), SIGNAL_HEADER_BYTES)
        for signal in file.signals
            header = first(signal)
            bytes_written += write_padded(io, getfield(header, field), padding)
        end
        if has_annotations
            header = EDF.Signal(file.annotations.header)
            bytes_written += write_padded(io, getfield(header, field), padding)
        end
    end
    return bytes_written
end

function write_data(io::IO, file::File)
    bytes_written = 0
    max_bytes = file.annotations.header.n_samples * 2
    for record_index in 1:file.header.n_records
        for (signal, samples) in file.signals
            sample_count = signal.n_samples
            start = (record_index - 1) * sample_count
            stop = min(start + sample_count, length(samples))
            bytes_written += Base.write(io, view(samples, (start + 1):stop))
        end
        if file.annotations !== nothing
            bytes_written += write_padded(io, file.annotations.records[record_index], max_bytes; pad=0x0)
        end
    end
    return bytes_written
end

"""
    EDF.write(io::IO, edf::EDF.File)
    EDF.write(path::AbstractString, edf::EDF.File)

Write the given `EDF.File` object to the given stream or file and return the number of
bytes written.
"""
write(io::IO, file::File) = write_header(io, file) + write_data(io, file)
write(path::AbstractString, edf::File) = Base.open(io -> write(io, edf), path, "w")
