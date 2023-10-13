#####
##### utilities
#####

# `allow_scientific` is only meaningful for `value::Number`. We allow passing it though,
# so `edf_write` can be more generic.
_edf_repr(value::Union{String,Char}; allow_scientific=nothing) = value
_edf_repr(date::Date; allow_scientific=nothing) = uppercase(Dates.format(date, dateformat"dd-u-yyyy"))
_edf_repr(date::DateTime; allow_scientific=nothing) = Dates.format(date, dateformat"dd\.mm\.yyHH\.MM\.SS")

"""
    sprintf_G_under_8(x) -> String

Return a string of length at most 8, written in either scientific notation (using capital-'E'),
or in decimal format, using as much precision as possible.
"""
function sprintf_G_under_8(x)
    shorten = str -> begin
        if contains(str, 'E')
            # Remove extraneous 0's in exponential notation
            str = replace(str, "E-0" => "E-")
            str = replace(str, "E+0" => "E+")
            # Remove any leading/trailing whitespace
            return strip(str)
        else
            # Decimal format. Call out to `trim_F`
            return trim_F(str)
        end
    end
    # Strategy:
    # `@printf("%0.NG", x)` means:
    # - `G`: Use the shortest representation: %E or %F. That is, scientific notation (with capital E) or decimals, whichever is shorted
    # - `.N`: (for literal `N`, like `5`): the maximum number of significant digits to be printed
    # However, `@printf("%0.NG", x)` may have more than `N` characters (e.g. presence of E, and the values for the exponent, the decimal place, etc)
    # So we start from 8 (most precision), and stop as soon as we get under 8 characters
    sig_8 = shorten(@sprintf("%.8G", x))
    length(sig_8) <= 8 && return sig_8
    sig_7 = shorten(@sprintf("%.7G", x))
    length(sig_7) <= 8 && return sig_7
    sig_6 = shorten(@sprintf("%.6G", x))
    length(sig_6) <= 8 && return sig_6
    sig_5 = shorten(@sprintf("%.5G", x))
    length(sig_5) <= 8 && return sig_5
    sig_4 = shorten(@sprintf("%.4G", x))
    length(sig_4) <= 8 && return sig_4
    sig_3 = shorten(@sprintf("%.3G", x))
    length(sig_3) <= 8 && return sig_3
    sig_2 = shorten(@sprintf("%.2G", x))
    length(sig_2) <= 8 && return sig_2
    sig_1 = shorten(@sprintf("%.1G", x))
    length(sig_1) <= 8 && return sig_1
    error("failed to fit number into EDF's 8 ASCII character limit: $x")
end

function trim_F(str)
    if contains(str, '.')
        # Remove trailing 0's after the decimal point
        str = rstrip(str, '0')
        # If the `.` is at the end now, strip it
        str = rstrip(str, '.')
    end
    # Removing leading or trailing whitespace
    str = strip(str)
    return str
end

function sprintf_F_under_8(x)
    shorten = trim_F
    # Strategy:
    # `@printf("%0.NF", x)` means:
    # - `F`: print with decimals
    # - `.N`: (for literal `N`, like `5`): the maximum number of digits to print after the decimal
    # However, `@printf("%0.NF", x)` may have more than `N` characters (e.g. digits to the left of the decimal point)
    # So we start from 8 (most precision), and stop as soon as we get under 8 characters
    sig_8 = shorten(@sprintf("%.8F", x))
    length(sig_8) <= 8 && return sig_8
    sig_7 = shorten(@sprintf("%.7F", x))
    length(sig_7) <= 8 && return sig_7
    sig_6 = shorten(@sprintf("%.6F", x))
    length(sig_6) <= 8 && return sig_6
    sig_5 = shorten(@sprintf("%.5F", x))
    length(sig_5) <= 8 && return sig_5
    sig_4 = shorten(@sprintf("%.4F", x))
    length(sig_4) <= 8 && return sig_4
    sig_3 = shorten(@sprintf("%.3F", x))
    length(sig_3) <= 8 && return sig_3
    sig_2 = shorten(@sprintf("%.2F", x))
    length(sig_2) <= 8 && return sig_2
    sig_1 = shorten(@sprintf("%.1F", x))
    length(sig_1) <= 8 && return sig_1
    error("failed to fit number into EDF's 8 ASCII character limit: $x")
end

function _edf_repr(x::Real; allow_scientific=false)
    if allow_scientific
        return sprintf_G_under_8(x)
    else
        return sprintf_F_under_8(x)
    end
end

_edf_metadata_repr(::Missing) = 'X'
_edf_metadata_repr(x) = _edf_repr(x)

function _edf_repr(metadata::T; allow_scientific=nothing) where {T<:Union{PatientID,RecordingID}}
    header = T <: RecordingID ? String["Startdate"] : String[]
    # None of the fields of `PatientID` or `RecordingID` are floating point, so we don't need
    # to worry about passing `allow_scientific=true`.
    return join([header; [_edf_metadata_repr(getfield(metadata, name)) for name in fieldnames(T)]], ' ')
end

function edf_write(io::IO, value, byte_limit::Integer; allow_scientific=false)
    edf_value = _edf_repr(value; allow_scientific)
    sizeof(edf_value) > byte_limit && error("EDF value exceeded byte limit (of $byte_limit bytes) while writing: `$value`. Representation: `$edf_value`")
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
    length(file.signals) <= 9999 || error("EDF does not allow files with more than 9999 signals")
    expected_bytes_written = BYTES_PER_FILE_HEADER + BYTES_PER_SIGNAL_HEADER * length(file.signals)
    bytes_written = 0
    bytes_written += edf_write(io, file.header.version, 8)
    bytes_written += edf_write(io, file.header.patient, 80)
    bytes_written += edf_write(io, file.header.recording, 80)
    bytes_written += edf_write(io, file.header.start, 16)
    bytes_written += edf_write(io, expected_bytes_written, 8)
    bytes_written += edf_write(io, file.header.is_contiguous ? "EDF+C" : "EDF+D", 44)
    bytes_written += edf_write(io, file.header.record_count, 8)
    bytes_written += edf_write(io, file.header.seconds_per_record, 8; allow_scientific=true)
    bytes_written += edf_write(io, length(file.signals), 4)
    signal_headers = SignalHeader.(file.signals)
    for (field_name, byte_limit, allow_scientific) in SIGNAL_HEADER_FIELDS
        for signal_header in signal_headers
            field = getfield(signal_header, field_name)
            bytes_written += edf_write(io, field, byte_limit; allow_scientific)
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
    # We do not pass `allow_scientific=true`, since that is not allowed for onset or durations
    bytes_written += Base.write(io, _edf_repr(tal.onset_in_seconds))
    if tal.duration_in_seconds !== nothing
        bytes_written += Base.write(io, 0x15)
        bytes_written += Base.write(io, _edf_repr(tal.duration_in_seconds)) # again, no `allow_scientific=true`
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
