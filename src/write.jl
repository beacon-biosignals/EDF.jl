#####
##### utilities
#####

edf_header_string(header_field_name, value::Union{String,Char}) = value
function edf_header_string(header_field_name, date::Date)
    return uppercase(Dates.format(date, dateformat"dd-u-yyyy"))
end
function edf_header_string(header_field_name, date::DateTime)
    return Dates.format(date, dateformat"dd\.mm\.yyHH\.MM\.SS")
end

# XXX this is really really hacky and doesn't support use of scientific notation
# where appropriate; keep in mind if you do improve this to support scientific
# notation, that scientific is NOT allowed in EDF annotation onset/duration fields
function edf_header_string(header_field_name, x::Real)
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
        roundtrip = parse(Float32, result)
        err = abs(roundtrip - x)
        tol = 1e-3
        if err > tol
            encoding_suggestion = header_field_name in
                                  (:digital_minimum, :digital_maximum, :physical_minimum,
                                   :physical_maximum) ?
                                  """
                                  We suggest choosing new encoding parameters to accomodate 8-character rendering.
                                  These can be verified with `EDF.edf_header_string`.
                                  """ : ""
            throw(ArgumentError("""
            Error writing header field $header_field_name
            Value: $x
            This value was encoded into an 8-character ASCII string: $result
            This yields roundtripping error: $err greater than the allowed tolerance ($tol)
            $encoding_suggestion"""))
        end
        return result
    end
    error("failed to fit header field $header_field_name into EDF's 8 ASCII character limit. Got: $x")
    return nothing
end

_edf_metadata_repr(header_field_name, ::Missing) = 'X'
_edf_metadata_repr(header_field_name, x) = edf_header_string(header_field_name, x)

function edf_header_string(header_field_name,
                           metadata::T) where {T<:Union{PatientID,RecordingID}}
    header = T <: RecordingID ? String["Startdate"] : String[]
    return join([header
                 [_edf_metadata_repr(name, getfield(metadata, name))
                  for name in fieldnames(T)]],
                ' ')
end

function edf_header_validate(c::AbstractChar)
    return Char(32) <= c <= Char(126)
end

function edf_header_validate(str::AbstractString)
    return all(edf_header_validate, str)
end
function edf_write(io::IO, header_field_name, value, byte_limit::Integer;
                   validate_ascii=true)
    edf_value = edf_header_string(header_field_name, value)
    if validate_ascii
        valid = edf_header_validate(edf_value)
        if !valid
            throw(ArgumentError("EDF+ specification requires all characters written in a string in the header to use US-ASCII characters between 32 and 126. Got: $edf_value from field $header_field_name"))
        end
    end
    sizeof(edf_value) > byte_limit &&
        error("EDF value exceeded byte limit (of $byte_limit bytes) while writing: $value for field $header_field_name")
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

function write_header(io::IO, file::File; validate_ascii=true)
    length(file.signals) <= 9999 ||
        error("EDF does not allow files with more than 9999 signals")
    expected_bytes_written = BYTES_PER_FILE_HEADER +
                             BYTES_PER_SIGNAL_HEADER * length(file.signals)
    bytes_written = 0
    bytes_written += edf_write(io, "version", file.header.version, 8; validate_ascii)
    bytes_written += edf_write(io, "patient", file.header.patient, 80; validate_ascii)
    bytes_written += edf_write(io, "recording", file.header.recording, 80; validate_ascii)
    bytes_written += edf_write(io, "start", file.header.start, 16; validate_ascii)
    bytes_written += edf_write(io, "", expected_bytes_written, 8; validate_ascii)
    bytes_written += edf_write(io, "is_contiguous",
                               file.header.is_contiguous ? "EDF+C" : "EDF+D", 44;
                               validate_ascii)
    bytes_written += edf_write(io, "record_count", file.header.record_count, 8;
                               validate_ascii)
    bytes_written += edf_write(io, "seconds_per_record", file.header.seconds_per_record, 8;
                               validate_ascii)
    bytes_written += edf_write(io, "", length(file.signals), 4; validate_ascii)
    signal_headers = SignalHeader.(file.signals)
    for (field_name, byte_limit) in SIGNAL_HEADER_FIELDS
        for signal_header in signal_headers
            field = getfield(signal_header, field_name)
            bytes_written += edf_write(io, field_name, field, byte_limit; validate_ascii)
        end
    end
    bytes_written += edf_write(io, "", ' ', 32 * length(file.signals); validate_ascii)
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

"""
    edf_annotation_time_string(time_in_seconds) -> String
    
Returns a string representing the time in seconds to the nearest 100 milliseconds.

Implemented by: `@sprintf("%.4f", time_in_seconds)`.

Resolution chosen to match EDFlib: <https://gitlab.com/Teuniz/EDFlib-Python/-/blob/75c991d73e3842d8bcbd0b8f32470e34cd676608/src/EDFlib/edfwriter.py#L791>.
"""
function edf_annotation_time_string(time_in_seconds)
    return @sprintf("%.4f", time_in_seconds)
end

function write_tal(io::IO, tal::TimestampedAnnotationList)
    bytes_written = 0
    if !signbit(tal.onset_in_seconds) # otherwise, the `-` will already be in number string
        bytes_written += Base.write(io, '+')
    end
    bytes_written += Base.write(io, edf_annotation_time_string(tal.onset_in_seconds))
    if tal.duration_in_seconds !== nothing
        bytes_written += Base.write(io, 0x15)
        bytes_written += Base.write(io, edf_annotation_time_string(tal.duration_in_seconds))
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
    validate_ascii = !is_bdf(file)
    return write_header(io, file; validate_ascii) + write_signals(io, file)
end

write(path::AbstractString, file::File) = Base.open(io -> write(io, file), path, "w")
