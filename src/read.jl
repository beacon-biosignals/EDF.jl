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
    recording_id = something(tryparse(RecordingID, recording_id_raw), String(recording_id_raw))

    start_raw = Base.read(io, 8)
    push!(start_raw, UInt8(' '))
    append!(start_raw, Base.read(io, 8))  # Add the time
    # Parsing the date per the given format will validate EDF+ item 2
    start = DateTime(String(start_raw), dateformat"dd\.mm\.yy HH\.MM\.SS")

    if year(start) <= 84  # 1985 is used as a clipping date
        start += Year(2000)
    else
        start += Year(1900)
    end

    # FIXME: EDF "avoids" the Y2K problem by punting it to the year 2084, after which
    # we ignore the above entirely and use `recording_id.startdate`. We could add a
    # check here on `year(today())`, but that will be dead code for the next 60+ years.

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
    fields = [String(Base.read(io, size)) for signal in 1:signal_count, (_, size) in SIGNAL_HEADER_FIELDS]
    signal_headers = [SignalHeader(strip(fields[i, 1]), strip(fields[i, 2]),
                                   strip(fields[i, 3]), parse_float(fields[i, 4]),
                                   parse_float(fields[i, 5]), parse_float(fields[i, 6]),
                                   parse_float(fields[i, 7]), strip(fields[i, 8]),
                                   parse(Int16, fields[i, 9])) for i in 1:size(fields, 1)]
    skip(io, 32 * signal_count) # reserved
    return signal_headers
end

#####
##### signal reading utilities
#####

function read_signals!(file::File)
    for record_index in 1:file.header.record_count, signal in file.signals
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
    Base.read!(file.io, view(signal.samples, record_start:record_stop))
    return nothing
end

function read_signal_record!(file::File, signal::AnnotationsSignal, record_index::Int)
    io_for_record = IOBuffer(Base.read(file.io, 2 * signal.samples_per_record))
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
    annotations = convert(Vector{String}, split(String(readuntil(io, 0x00)), '\x14'; keepempty=false))
    return TimestampedAnnotationList(onset_in_seconds, duration_in_seconds, annotations)
end

function read_tal_onset_sign(io::IO)
    sign = Base.read(io, UInt8)
    sign === 0x2b && return 1
    sign === 0x2d && return -1
    error("starting byte of a TAL must be '+' or '-'; found $sign")
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
    signals = Union{Signal,AnnotationsSignal}[]
    for header in read_signal_headers(io, signal_count)
        if header.label == ANNOTATIONS_SIGNAL_LABEL
            push!(signals, AnnotationsSignal(header))
        else
            push!(signals, Signal(header))
        end
    end
    return File(io, file_header, signals)
end

"""
    EDF.read!(file::File)

Read all EDF sample and annotation data from `file.io` into `file.signals` and
`file.annotations`, returning `file`. If `eof(file.io)`, return `file` unmodified.
"""
function read!(file::File)
    (isopen(file.io) || !eof(file.io)) && read_signals!(file)
    return file
end

"""
    EDF.read(io::IO)

Return `EDF.read!(EDF.File(io))`.

See also: [`EDF.File`](@ref), [`EDF.read!`](@ref)
"""
read(io::IO) = read!(File(io))

"""
    EDF.read(path::AbstractString)

Return `open(EDF.read, path)`.
"""
read(path::AbstractString) = open(read, path)
