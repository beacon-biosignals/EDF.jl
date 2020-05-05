#####
##### utilities
#####

_edf_repr(value::Union{String,Char}) = value
_edf_repr(date::Date) = uppercase(Dates.format(date, dateformat"dd-u-yyyy"))
_edf_repr(date::DateTime) = Dates.format(date, dateformat"dd\.mm\.yyHH\.MM\.SS")

function _edf_repr(x::Real)
    result = missing
    if isinteger(x)
        str = string(trunc(Int, x))
        if length(str) <= 8
            result = str
        end
    else
        fpart, ipart = modf(x)
        ipart_str = string('-'^signbit(x), Int(ipart))
        fpart_str = @sprintf "%.7f" abs(fpart)
        fpart_str = fpart_str[3:end] # remove leading `0.`
        if length(ipart_str) < 7
            result = ipart_str * '.' * fpart_str[1:(8 - length(ipart_str))]
        elseif length(ipart_str) <= 8
            result = ipart_str
        end
    end
    if !ismissing(result)
        if all(c -> c in ('0', '.', '-'), result)
            x == 0 && return result
        else
            return result
        end
    end
    error("failed to fit number into EDF's 8 ASCII character limit: $x")
end

_edf_metadata_repr(::Missing) = 'X'
_edf_metadata_repr(x) = _edf_repr(x)

function _edf_repr(metadata::T) where T<:Union{PatientID,RecordingID}
    header = T <: RecordingID ? String["Startdate"] : String[]
    return join([header; [_edf_metadata_repr(getfield(metadata, name)) for name in fieldnames(T)]], ' ')
end

function edf_write(io::IO, value, byte_limit::Integer)
    edf_value = _edf_repr(value)
    @assert isascii(edf_value)
    size = length(edf_value)
    bytes_written = Base.write(io, edf_value)
    while bytes_written < byte_limit
        bytes_written += Base.write(io, UInt8(' '))
    end
    return bytes_written
end

#####
##### `write_header`
#####

function write_header(io::IO, file::File)
    length(file.signals) <= 9999 || error("EDF does not allow files with more than 9999 signals")
    bytes_written = 0
    bytes_written += edf_write(io, file.header.version, 8)
    bytes_written += edf_write(io, file.header.patient, 80)
    bytes_written += edf_write(io, file.header.recording, 80)
    bytes_written += edf_write(io, file.header.start, 16)
    bytes_written += edf_write(io, bytes_written, 8)
    bytes_written += edf_write(io, file.header.is_contiguous ? "EDF+C" : "EDF+D", 44)
    bytes_written += edf_write(io, file.header.record_count, 8)
    bytes_written += edf_write(io, file.header.seconds_per_record, 8)
    bytes_written += edf_write(io, length(file.signals), 4)
    signal_headers = SignalHeader.(file.signals)
    for (field_name, byte_limit) in SIGNAL_HEADER_FIELDS
        for signal_header in signal_headers
            field = getfield(signal_header, field_name)
            bytes_written += edf_write(io, field, byte_limit)
        end
    end
    bytes_written += edf_write(io, ' ', 32 * length(file.signals))
    @assert bytes_written == BYTES_PER_FILE_HEADER + BYTES_PER_SIGNAL_HEADER * length(file.signals)
    return bytes_written
end

#####
##### `write_signals`
#####

function write_signals(io::IO, file::File)
    bytes_written = 0
    for record_index in 1:file.header.record_count
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
        if !signbit(tal.onset_in_seconds) # otherwise, the `-` will already be in number string
            bytes_written += Base.write(io, '+')
        end
        bytes_written += Base.write(io, _edf_repr(tal.onset_in_seconds))
        if tal.duration_in_seconds !== nothing
            bytes_written += Base.write(io, 0x15)
            bytes_written += Base.write(io, _edf_repr(tal.duration_in_seconds))
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
