#####
##### utilities
#####

_edf_write(io::IO, value::Union{String,Char,Integer}) = Base.write(io, value)
_edf_write(io::IO, date::Date) = Base.write(io, uppercase(Dates.format(date, dateformat"dd-u-yyyy")))
_edf_write(io::IO, date::DateTime) = Base.write(io, Dates.format(date, dateformat"dd\.mm\.yyHH\.MM\.SS"))
_edf_write(io::IO, x::AbstractFloat) = Base.write(io, string(isinteger(x) ? trunc(Int, x) : x))

function _edf_write(io::IO, metadata::T) where T<:Union{PatientID,RecordingID}
    bytes_written = 0
    for name in fieldnames(T)
        field = getfield(metadata, name)
        if T <: RecordingID && name === :startdate
            bytes_written += _edf_write(io, "Startdate ")
        end
        bytes_written += field isa Missing ? Base.write(io, 'X') : _edf_write(io, field)
        bytes_written += Base.write(io, ' ')
    end
    return bytes_written
end

function edf_write(io::IO, value, byte_limit::Integer; pad::UInt8=UInt8(' '))
    bytes_written = _edf_write(io, value)
    bytes_written <= byte_limit || error("Written value $value contains more bytes than limit $byte_limit")
    while bytes_written < byte_limit
        bytes_written += Base.write(io, pad)
    end
    return bytes_written
end

#####
##### `write_header`
#####

const BYTES_PER_FILE_HEADER = 256

const BYTES_PER_SIGNAL_HEADER = 256

function write_header(io::IO, file::File)
    bytes_written = BYTES_PER_FILE_HEADER + BYTES_PER_SIGNAL_HEADER * length(file.signals)
    actual_bytes_written = 0
    actual_bytes_written += edf_write(io, file.header.version, 8)
    actual_bytes_written += edf_write(io, file.header.patient, 80)
    actual_bytes_written += edf_write(io, file.header.recording, 80)
    actual_bytes_written += edf_write(io, file.header.start, 16)
    actual_bytes_written += edf_write(io, bytes_written, 8)
    actual_bytes_written += edf_write(io, file.header.is_contiguous ? "EDF+C" : "EDF+D", 44)
    actual_bytes_written += edf_write(io, file.header.record_count, 8)
    actual_bytes_written += edf_write(io, file.header.seconds_per_record, 8)
    actual_bytes_written += edf_write(io, length(file.signals), 4)
    signal_headers = SignalHeader.(file.signals)
    for (field_name, byte_limit) in [(:label, 16),
                                     (:transducer_type, 80),
                                     (:physical_dimension, 8),
                                     (:physical_minimum, 8),
                                     (:physical_maximum, 8),
                                     (:digital_minimum, 8),
                                     (:digital_maximum, 8),
                                     (:prefilter, 8),
                                     (:samples_per_record, 8)]
        for signal_header in signal_headers
            field = getfield(signal_header, field_name)
            actual_bytes_written += edf_write(io, field, byte_limit)
        end
    end
    actual_bytes_written += edf_write(io, ' ', 32 * length(file.signals))
    @assert actual_bytes_written == bytes_written
    return bytes_written
end

#####
##### `write_signals`
#####

function write_signals(io::IO, file::File)
    bytes_written = 0
    for record_index in 1:file.header.record_count
        past_first_annotation_signal_in_record = false
        for signal in file.signals
            bytes_written += write_signal_record(io, signal, record_index)
        end
    end
    return bytes_written
end

function write_signal_record(io::IO, signal::Signal, record_index::Int)
    record_start = 1 + (record_index - 1) * signal.header.samples_per_record
    record_stop = record_index * signal.header.samples_per_record
    record_stop = min(record_stop, length(signal.samples))
    return Base.write(io, view(signal.samples, record_start:record_stop))
end

function write_signal_record(io::IO, signal::AnnotationsSignal, record_index::Int)
    bytes_written = 0
    for tal in signal.records[record_index]
        bytes_written += Base.write(io, signbit(tal.onset_in_seconds) ? '-' : '+')
        bytes_written += _edf_write(io, tal.onset_in_seconds)
        if tal.duration_in_seconds !== nothing
            bytes_written += Base.write(io, 0x15)
            bytes_written += _edf_write(io, tal.duration_in_seconds)
        end
        bytes_written += Base.write(io, 0x14)
        for annotation in tal.annotations
            bytes_written += Base.write(io, annotation)
            bytes_written += Base.write(io, 0x14)
        end
        bytes_written += Base.write(io, 0x00)
    end
    bytes_per_record = 2 * signal.samples_per_record
    while bytes_written < bytes_per_record
        bytes_written += Base.write(io, 0x00)
    end
    return bytes_written
end

#####
##### API functions
#####

"""
    EDF.write(io::IO, file::EDF.File)
    EDF.write(path::AbstractString, file::EDF.File)

Write `file` to the given output, returning the number of bytes written.
"""
write(io::IO, file::File) = write_header(io, file) + write_signals(io, file)
write(path::AbstractString, file::File) = Base.open(io -> write(io, file), path, "w")
