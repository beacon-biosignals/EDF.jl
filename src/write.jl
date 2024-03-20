#####
##### utilities
#####

_edf_repr(value::Union{String,Char}) = value
_edf_repr(date::Date) = uppercase(Dates.format(date, dateformat"dd-u-yyyy"))
_edf_repr(date::DateTime) = Dates.format(date, dateformat"dd\.mm\.yyHH\.MM\.SS")

# XXX this is really really hacky and doesn't support use of scientific notation
# where appropriate; keep in mind if you do improve this to support scientific
# notation, that scientific is NOT allowed in EDF annotation onset/duration fields
function _edf_repr(x::Real)
    result = missing
    if isinteger(x)
        str = string(trunc(Int, x))
        if length(str) <= 8
            result = str
        end
    else
        fpart, ipart = modf(x)
        ipart_str = string('-'^signbit(x), Int(abs(ipart))) # handles `-0.0` case
        fpart_str = @sprintf "%.7f" abs(fpart)
        fpart_str = fpart_str[3:end] # remove leading `0.`
        if length(ipart_str) < 7
            result = ipart_str * '.' * fpart_str[1:(7 - length(ipart_str))]
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
    return nothing
end

_edf_metadata_repr(::Missing) = 'X'
_edf_metadata_repr(x) = _edf_repr(x)

function _edf_repr(metadata::T) where {T<:Union{PatientID,RecordingID}}
    header = T <: RecordingID ? String["Startdate"] : String[]
    return join([header;
                 [_edf_metadata_repr(getfield(metadata, name)) for name in fieldnames(T)]],
                ' ')
end

function edf_write(io::IO, value, byte_limit::Integer)
    edf_value = _edf_repr(value)
    sizeof(edf_value) > byte_limit &&
        error("EDF value exceeded byte limit (of $byte_limit bytes) while writing: $value")
    bytes_written = Base.write(io, edf_value)
    while bytes_written < byte_limit
        bytes_written += Base.write(io, UInt8(' '))
    end
    return bytes_written
end

# NOTE: The fast-path in `Base.write` that uses `unsafe_write` will include alignment
# padding bytes, which is fine for `Int16` but causes `Int24` to write an extra byte
# for each value. To get around this, we'll fall back to a naive implementation when
# the size of the element type doesn't match its aligned size. (See also `read_to!`)
function write_from(io::IO, x::AbstractArray{T}) where {T}
    if sizeof(T) == Base.aligned_sizeof(T)
        return Base.write(io, x)
    else
        n = 0
        for xi in x
            n += Base.write(io, xi)
        end
        return n
    end
end

#####
##### `write_header`
#####

function write_header(io::IO, file::File)
    length(file.signals) <= 9999 ||
        error("EDF does not allow files with more than 9999 signals")
    expected_bytes_written = BYTES_PER_FILE_HEADER +
                             BYTES_PER_SIGNAL_HEADER * length(file.signals)
    bytes_written = 0
    bytes_written += edf_write(io, file.header.version, 8)
    bytes_written += edf_write(io, file.header.patient, 80)
    bytes_written += edf_write(io, file.header.recording, 80)
    bytes_written += edf_write(io, file.header.start, 16)
    bytes_written += edf_write(io, expected_bytes_written, 8)
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
    @assert bytes_written == expected_bytes_written
    return bytes_written
end

#####
##### `write_signals`
#####

function write_signals(io::IO, file::File)
    bytes_written = 0
    for record_index in 1:(file.header.record_count)
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
    return write_from(io, view(signal.samples, record_start:record_stop))
end

function write_signal_record(io::IO, signal::AnnotationsSignal, record_index::Int)
    bytes_written = 0
    for tal in signal.records[record_index]
        bytes_written += write_tal(io, tal)
    end
    bytes_per_record = 2 * signal.samples_per_record
    while bytes_written < bytes_per_record
        bytes_written += Base.write(io, 0x00)
    end
    return bytes_written
end

function write_tal(io::IO, tal::TimestampedAnnotationList)
    bytes_written = 0
    if !signbit(tal.onset_in_seconds) # otherwise, the `-` will already be in number string
        bytes_written += Base.write(io, '+')
    end
    bytes_written += Base.write(io, _edf_repr(tal.onset_in_seconds))
    if tal.duration_in_seconds !== nothing
        bytes_written += Base.write(io, 0x15)
        bytes_written += Base.write(io, _edf_repr(tal.duration_in_seconds))
    end
    if isempty(tal.annotations)
        bytes_written += Base.write(io, 0x14)
        bytes_written += Base.write(io, 0x14)
    else
        for annotation in tal.annotations
            bytes_written += Base.write(io, 0x14)
            bytes_written += Base.write(io, annotation)
            bytes_written += Base.write(io, 0x14)
        end
    end
    bytes_written += Base.write(io, 0x00)
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
function write(io::IO, file::File)
    if !file.header.is_contiguous && !any(s -> s isa AnnotationsSignal, file.signals)
        message = """
                  `file.header.is_contiguous` is `false` but `file.signals` does not contain
                  an `AnnotationsSignal`; this is required as per the EDF+ specification for
                  noncontiguous files in order to specify the start time of each data record
                  (see section 2.2.4 for details).
                  """
        throw(ArgumentError(message))
    end
    return write_header(io, file) + write_signals(io, file)
end

write(path::AbstractString, file::File) = Base.open(io -> write(io, file), path, "w")
