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

function read_file_and_signal_headers(io::IO)
    file_header, header_byte_count, signal_count = read_file_header(io)
    fields = [String(Base.read(io, size)) for signal in 1:signal_count, size in SIGNAL_HEADER_BYTES]
    signal_headers = [SignalHeader(strip(fields[i,1]), strip(fields[i,2]),
                                   strip(fields[i,3]), parse_float(fields[i,4]),
                                   parse_float(fields[i,5]), parse_float(fields[i,6]),
                                   parse_float(fields[i,7]), strip(fields[i,8]),
                                   parse(Int16, fields[i,9])) for i in 1:size(fields, 1)]
    skip(io, 32 * signal_count) # Reserved
    position(io) == header_byte_count || error("Incorrect number of bytes in the header. " *
                                               "Expected $header_byte_count but was $(position(io))")
    return file_header, signal_headers
end

function read_file_header(io::IO)
    version = strip(String(Base.read(io, 8)))

    patient_id_raw = strip(String(Base.read(io, 80)))
    patient_id = something(tryparse(PatientID, patient_id_raw), String(patient_id_raw))

    recording_id_raw = strip(String(Base.read(io, 80)))
    recording_id = something(tryparse(RecordingID, recording_id_raw), String(recording_id_raw))

    start_raw = Base.read(io, 8)
    push!(start_raw, 0x20)  # Push a space separator
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

    header_byte_count = parse(Int, String(Base.read(io, 8)))
    reserved = String(Base.read(io, 44))
    is_contiguous = !startswith(reserved, "EDF+D")
    record_count = parse(Int, String(Base.read(io, 8)))
    seconds_per_record = parse(Float64, String(Base.read(io, 8)))
    signal_count = parse(Int, String(Base.read(io, 4)))

    header = FileHeader(version, patient_id, recording_id, start, is_contiguous,
                        record_count, seconds_per_record)
    return header, header_byte_count, signal_count
end

function extract_annotations_signal_header!(headers::Vector{SignalHeader})
    index = findfirst(header -> header.label == ANNOTATIONS_SIGNAL_LABEL, headers)
    index === nothing && return nothing
    annotations_signal_header = AnnotationsSignalHeader(headers[index].samples_per_record, index)
    deleteat!(headers, index)
    return annotations_signal_header
end

#####
##### signal reading utilities
#####

function read_signals!(file::File)
    for signal in file.signals
        resize!(signal.samples, file.header.record_count * signal.header.samples_per_record)
    end
    if file.annotations === nothing
        for record in 1:file.header.record_count, signal in file.signals
            read_signal_record!(file, signal, record)
        end
    else
        buffer = Vector{UInt8}(undef, 2 * file.annotations.header.samples_per_record)
        for record in 1:file.header.record_count
            for (index, signal) in enumerate(file.signals)
                if file.annotations.header.original_index == index
                    read_annotations_signal_record!(file, buffer, record)
                end
                read_signal_record!(file, signal, record)
            end
            if file.annotations.header.original_index == lastindex(file.signals) + 1
                read_annotations_signal_record!(file, buffer, record)
            end
        end
    end
    @assert eof(file.io)
    return nothing
end

function read_signal_record!(file::File, signal::Signal, record::Int)
    record_start = 1 + (record - 1) * signal.header.samples_per_record
    record_stop = record * signal.header.samples_per_record
    Base.read!(file.io, view(signal.samples, record_start:record_stop))
    return nothing
end

#####
##### annotation reading utilities
#####

function read_annotations_signal_record!(file::File, buffer, record::Int)
    Base.read!(file.io, buffer)
    tals = TimestampedAnnotationList[]
    # TODO
    push!(file.annotations.records, tals)
    return
end

# function read_annotations!(records::Vector{DataRecord}, data::Vector{UInt8}, index::Integer)
#     record = IOBuffer(data)
#     annotations = Vector{TimestampAnnotation}()
#     record_annotation = read_record_annotation(record)
#     while !eof(record) && Base.peek(record) != 0x0
#         push!(annotations, read_timestamp_annotation(record))
#     end
#     if isempty(annotations)
#         annotations = nothing
#     end
#     push!(records, record_annotation => annotations)
#     return nothing
# end

# function read_record_annotation(io::IO)
#     sign = read_sign(io)
#     offset = sign * parse(Float64, String(readuntil(io, 0x14)))
#     if Base.peek(io) !== 0x0
#         events = read_events(io)
#     else
#         events = nothing
#         Base.skip(io, 1)
#     end
#     return RecordAnnotation(offset, events)
# end

# function read_timestamp_annotation(io::IO)
#     sign = read_sign(io)
#     raw = readuntil(io, 0x14)
#     timestamp = split(String(raw), '\x15'; keepempty=false)
#     offset = flipsign(parse(Float64, popfirst!(timestamp)), sign)
#     if isempty(timestamp)
#         duration = nothing
#     else
#         duration = parse(Float64, popfirst!(timestamp))
#     end
#     events = read_events(io)
#     events !== nothing || error("No events found for timestamp annotation at offset $offset")
#     return TimestampAnnotation(offset, duration, events)
# end
#
# function read_sign(io::IO)
#     sign = Base.read(io, UInt8)
#     sign === 0x2b || sign === 0x2d || error("Starting byte of annotation must be '+' or '-'.")
#     return sign === 0x2b ? 1 : -1
# end
#
# function read_events(io::IO)
#     raw = readuntil(io, 0x0)
#     events = split(String(raw), '\x14'; keepempty=false)
#     events = convert(Vector{String}, events)
#     return isempty(events) ? nothing : events
# end

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
    file_header, signal_headers = read_file_and_signal_headers(io)
    annotations_header = extract_annotations_signal_header!(signal_headers)
    annotations = annotations_header === nothing ? nothing : AnnotationsSignal(annotations_header)
    return File(io, file_header, Signal.(signal_headers), annotations)
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
