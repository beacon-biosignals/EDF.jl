#####
##### parsing utilities
#####

function Base.tryparse(::Type{PatientID}, raw::AbstractString)
    metadata = split(raw, ' '; keepempty=false)
    length(metadata) == 4 || return nothing
    code_raw, sex_raw, dob_raw, name_raw = metadata
    length(sex_raw) == 1 || return nothing
    code = edf_unknown(code_raw)
    sex = edf_unknown(first, sex_raw)
    dob = edf_unknown(parse_date, dob_raw)
    dob === nothing && return nothing
    name = edf_unknown(name_raw)
    return PatientID(code, sex, dob, name)
end

function Base.tryparse(::Type{RecordingID}, raw::AbstractString)
    startswith(raw, "Startdate") || return nothing
    metadata = split(chop(raw; head=9, tail=0), ' '; keepempty=false)
    length(metadata) == 4 || return nothing
    start_raw, admin_raw, tech_raw, equip_raw = metadata
    startdate = edf_unknown(parse_date, start_raw)
    startdate === nothing && return nothing
    admincode = edf_unknown(admin_raw)
    technician = edf_unknown(tech_raw)
    equipment = edf_unknown(equip_raw)
    return RecordingID(startdate, admincode, technician, equipment)
end

# EDF does not specify what to do if the month or day is not in a valid range
# so if it is not we snap month or day to "01" and try again
function parse_header_date(date_str::AbstractString)
    m = match(r"^(\d{2})\.(\d{2})\.(\d{2}) (\d{2})\.(\d{2})\.(\d{2})$", date_str)
    if m === nothing
        throw(ArgumentError("Malformed date string: expected 'dd.mm.yy HH.MM.SS', " *
                            "got '$date_str'"))
    end
    day, month, year, hour, minute, second = parse.(Int, m.captures)
    if year <= 84
        year += 2000
    else
        year += 1900
    end

    # FIXME: EDF "avoids" the Y2K problem by punting it to the year 2084, after which
    # we ignore the above entirely and use `recording_id.startdate`. We could add a
    # check here on `year(today())`, but that will be dead code for the next 60+ years.

    month = clamp(month, 1, 12)
    day = clamp(day, 1, daysinmonth(year, month))
    hour = clamp(hour, 0, 23)
    minute = clamp(minute, 0, 59)
    second = clamp(second, 0, 59)
    return DateTime(year, month, day, hour, minute, second)
end

parse_float(raw::AbstractString) = something(tryparse(Float32, raw), NaN32)

parse_date(raw::AbstractString) = tryparse(Date, raw, dateformat"d-u-y")

"""
    edf_unknown([f,] field::String)

Check whether the given text is simply "X", which per the EDF+ specification means that the
value is unknown, not applicable, or must be made anonymous, and if so return `missing`,
otherwise return the result of applying `f` to the given text. If unspecified, `f` defaults
to `identity`.
"""
edf_unknown(f, field::AbstractString) = field == "X" ? missing : f(field)
edf_unknown(field::AbstractString) = edf_unknown(identity, field)

#####
##### header reading utilities
#####

function read_file_header(io::IO)
    version = strip(String(Base.read(io, 8)))

    patient_id_raw = strip(String(Base.read(io, 80)))
    patient_id = something(tryparse(PatientID, patient_id_raw), String(patient_id_raw))

    recording_id_raw = strip(String(Base.read(io, 80)))
    recording_id = something(tryparse(RecordingID, recording_id_raw),
                             String(recording_id_raw))

    start_raw = Base.read(io, 8)
    push!(start_raw, UInt8(' '))
    append!(start_raw, Base.read(io, 8))  # Add the time
    # Parsing the date per the given format will validate EDF+ item 2
    start = parse_header_date(String(start_raw))

    # NOTE: These 8 bytes are supposed to define the byte count of the header,
    # which in reality is trivially computable from constants defined by the
    # specification + directly available information in the header already. I'm
    # not sure why the EDF standard requires that it be written out at all; AFAICT
    # it only serves as a potential bug source for readers/writers that might write
    # the incorrect value here. Since we don't actually use this value anywhere in
    # our read/write process, we skip it here.
    skip(io, 8)

    reserved = String(Base.read(io, 44))
    is_contiguous = !startswith(reserved, "EDF+D")
    record_count = parse(Int, String(Base.read(io, 8)))
    seconds_per_record = parse(Float64, String(Base.read(io, 8)))
    signal_count = parse(Int, String(Base.read(io, 4)))
    return FileHeader(version, patient_id, recording_id, start, is_contiguous,
                      record_count, seconds_per_record), signal_count
end

function read_signal_headers(io::IO, signal_count)
    fields = [String(Base.read(io, size))
              for signal in 1:signal_count, (_, size) in SIGNAL_HEADER_FIELDS]
    signal_headers = [SignalHeader(strip(fields[i, 1]), strip(fields[i, 2]),
                                   strip(fields[i, 3]), parse_float(fields[i, 4]),
                                   parse_float(fields[i, 5]), parse_float(fields[i, 6]),
                                   parse_float(fields[i, 7]), strip(fields[i, 8]),
                                   parse(Int32, fields[i, 9])) for i in 1:size(fields, 1)]
    skip(io, 32 * signal_count) # reserved
    return signal_headers
end

#####
##### signal reading utilities
#####

# NOTE: The fast-path in `Base.read!` that uses `unsafe_read` will read too much when
# the element type is `Int24`, since it will try to include the alignment padding for
# each value read and will thus read too much. To get around this, we'll fall back to
# a naive implementation when the size of the element type doesn't match its aligned
# size. (See also `write_from`)
function read_to!(io::IO, x::AbstractArray{T}) where {T}
    if sizeof(T) == Base.aligned_sizeof(T)
        Base.read!(io, x)
    else
        @inbounds for i in eachindex(x)
            x[i] = Base.read(io, T)
        end
    end
    return x
end

function read_signals!(file::File)
    for record_index in 1:(file.header.record_count), signal in file.signals
        read_signal_record!(file, signal, record_index)
    end
    return nothing
end

function read_signal_record!(file::File, signal::Signal, record_index::Int)
    if isempty(signal.samples)
        resize!(signal.samples, file.header.record_count * signal.header.samples_per_record)
    end
    record_start = 1 + (record_index - 1) * signal.header.samples_per_record
    record_stop = record_index * signal.header.samples_per_record
    read_to!(file.io, view(signal.samples, record_start:record_stop))
    return nothing
end

function read_signal_record!(file::File, signal::AnnotationsSignal, record_index::Int)
    bytes_per_sample = sizeof(sample_type(file))
    io_for_record = IOBuffer(Base.read(file.io,
                                       bytes_per_sample * signal.samples_per_record))
    tals_for_record = TimestampedAnnotationList[]
    while !eof(io_for_record) && Base.peek(io_for_record) != 0x00
        push!(tals_for_record, read_tal(io_for_record))
    end
    push!(signal.records, tals_for_record)
    return nothing
end

function read_tal(io::IO)
    sign = read_tal_onset_sign(io)
    bytes = readuntil(io, 0x14)
    timestamp = split(String(bytes), '\x15'; keepempty=false)
    onset_in_seconds = flipsign(parse(Float64, timestamp[1]), sign)
    duration_in_seconds = length(timestamp) == 2 ? parse(Float64, timestamp[2]) : nothing
    annotations = convert(Vector{String},
                          split(String(readuntil(io, 0x00)), '\x14'; keepempty=true))
    isempty(last(annotations)) && pop!(annotations)
    return TimestampedAnnotationList(onset_in_seconds, duration_in_seconds, annotations)
end

function read_tal_onset_sign(io::IO)
    sign = Base.read(io, UInt8)
    sign === 0x2b && return 1
    sign === 0x2d && return -1
    error("starting byte of a TAL must be '+' or '-'; found $sign")
    return nothing
end

#####
##### API functions
#####

"""
    EDF.File(io::IO)

Return an `EDF.File` instance that wraps the given `io`, as well as EDF-formatted
file, signal, and annotation headers that are read from `io`. This constructor
only reads headers, not the subsequent sample data; to read the subsequent sample
data from `io` into the returned `EDF.File`, call `EDF.read!(file)`.
"""
function File(io::IO)
    file_header, signal_count = read_file_header(io)
    T = sample_type(file_header)
    signals = Union{Signal{T},AnnotationsSignal}[]
    for header in read_signal_headers(io, signal_count)
        if header.label in ANNOTATIONS_SIGNAL_LABEL
            push!(signals, AnnotationsSignal(header))
        else
            push!(signals, Signal{T}(header, T[]))
        end
    end
    file_size = _size(io)
    if file_size > 0
        bytes_left = file_size - position(io)
        total_expected_samples = sum(signals) do signal
            if signal isa Signal
                return signal.header.samples_per_record
            else
                return signal.samples_per_record
            end
        end
        readable_records = div(div(bytes_left, sizeof(T)), total_expected_samples)
        if file_header.record_count > readable_records
            @warn("Number of data records in file header does not match file size. " *
                  "Skipping $(file_header.record_count - readable_records) truncated " *
                  "data record(s).")
            file_header = FileHeader(file_header.version,
                                     file_header.patient,
                                     file_header.recording,
                                     file_header.start,
                                     file_header.is_contiguous,
                                     readable_records,
                                     file_header.seconds_per_record)
        end
    end
    return File(io, file_header, signals)
end

_size(io::IOStream) = filesize(io)
_size(io::IOBuffer) = io.size

# NOTE: We're using -1 here as a type-stable way of denoting an unknown size.
# Also note that some `IO` types may have a specific method for `stat` which would be
# convenient except that it's difficult to determine since `stat` has an untyped method
# that won't work for `IO` types despite `applicable`/`hasmethod` thinking it applies.
# Instead, we'll check for the availability of seeking-related methods and try to use
# those to determine the size, returning -1 if the requisite methods don't apply.
function _size(io::IO)
    applicable(position, io) || return -1
    here = position(io)
    applicable(seek, io, here) && applicable(seekend, io) || return -1
    seekend(io)
    nbytes = position(io)
    seek(io, here)
    return nbytes
end

"""
    EDF.is_bdf(file)

Return `true` if `file` is a BDF (BioSemi Data Format) file, otherwise `false`.
"""
is_bdf(file::File) = is_bdf(file.header)
is_bdf(header::FileHeader) = header.version == "\xffBIOSEMI"

"""
    EDF.sample_type(file::EDF.File{T})

Return the encoded type `T` of the samples stored in `file`.
"""
sample_type(file::File{T}) where {T} = T
sample_type(header::FileHeader) = is_bdf(header) ? BDF_SAMPLE_TYPE : EDF_SAMPLE_TYPE

"""
    EDF.read!(file::File)

Read all EDF sample and annotation data from `file.io` into `file.signals` and
`file.annotations`, returning `file`. If `eof(file.io)`, return `file` unmodified.
"""
function read!(file::File)
    isopen(file.io) && !eof(file.io) && read_signals!(file)
    return file
end

"""
    EDF.read(io::IO)

Return `EDF.read!(EDF.File(io))`.

See also: [`EDF.File`](@ref), [`EDF.read!`](@ref)
"""
read(io::IO) = read!(File(io))

"""
    EDF.read(path)

Return `open(EDF.read, path)`.
"""
read(path) = open(read, path)
