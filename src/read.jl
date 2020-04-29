#####
##### Parsing utilities
#####

function Base.tryparse(::Type{PatientID}, raw::AbstractString)
    s = split(raw, ' '; keepempty=false)
    length(s) == 4 || return
    code_raw, sex_raw, dob_raw, name_raw = s
    length(sex_raw) == 1 || return
    code = edf_unknown(code_raw)
    sex = edf_unknown(first, sex_raw)
    dob = edf_unknown(raw -> tryparse(Date, raw, dateformat"d-u-y"), dob_raw)
    dob === nothing && return
    name = edf_unknown(name_raw)
    return PatientID(code, sex, dob, name)
end

function Base.tryparse(::Type{RecordingID}, raw::AbstractString)
    s = split(raw, ' '; keepempty=false)
    length(s) == 5 || return
    first(s) == "Startdate" || return
    _, start_raw, admin_raw, tech_raw, equip_raw = s
    startdate = edf_unknown(raw -> tryparse(Date, raw, dateformat"d-u-y"), start_raw)
    startdate === nothing && return
    admincode = edf_unknown(admin_raw)
    technician = edf_unknown(tech_raw)
    equipment = edf_unknown(equip_raw)
    return RecordingID(startdate, admincode, technician, equipment)
end

parse_float(raw::AbstractString) = something(tryparse(Float32, raw), NaN32)

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
##### Reading EDF Files
#####


function read_file_and_signal_headers(io::IO)
    file_header, header_byte_count, signal_count = read_file_header(io)
    fields = [method(String(Base.read(io, size)))
              for signal in 1:signal_count, (size, method) in zip(FIELD_SIZES, PARSE_METHODS)]
    T = Union{SignalHeader,AnnotationListHeader}
    signal_headers = T[SignalHeader(fields[i, :]...) for i in 1:size(fields, 1)]
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
    continuous = !startswith(reserved, "EDF+D")
    n_records = parse(Int, String(Base.read(io, 8)))
    duration = parse(Float64, String(Base.read(io, 8)))
    signal_count = parse(Int, String(Base.read(io, 4)))

    header = FileHeader(version, patient_id, recording_id, start,
                        continuous, n_records, duration)
    return header, header_byte_count, signal_count
end

const FIELD_SIZES = [16, 80, 8, 8, 8, 8, 8, 80, 8]
const PARSE_METHODS = Function[strip, strip, strip, parse_float, parse_float, parse_float, parse_float, strip, x -> parse(Int16, x)]

function read_signals(io::IO, file_header::FileHeader, signal_headers::Vector)
    annotation_header = findfirst(header -> header.label == "EDF Annotations", signal_headers)
    if annotation_header !== nothing
        signal_headers[annotation_header] = AnnotationListHeader(signal_headers[annotation_header])
    end
    signal_samples = [samples(signal) for signal in signal_headers]
    for record in 1:file_header.n_records, (index, header) in enumerate(signal_headers)
        data = Base.read(io, 2 * header.n_samples)
        read_data!(signal_samples[index], data, header)
    end
    if annotation_header !== nothing
        header = splice!(signal_headers, annotation_header)
        records = splice!(signal_samples, annotation_header)
        annotations = AnnotationList(header, records)
    else
        annotations = nothing
    end
    signals = Signal.(signal_headers, signal_samples)
    @assert eof(io)
    return signals, annotations
end

read_data!(samples::Vector{Int16}, data::Vector{UInt8}, ::SignalHeader) = append!(samples, reinterpret(Int16, data))

function read_data!(samples::Vector{DataRecord}, data::Vector{UInt8}, ::AnnotationListHeader)
    record = IOBuffer(data)
    annotations = Vector{TimestampAnnotation}()
    record_annotation = read_record_annotation(record)
    while !eof(record) && Base.peek(record) != 0x0
        push!(annotations, read_timestamp_annotation(record))
    end
    if isempty(annotations)
        annotations = nothing
    end
    push!(samples, record_annotation => annotations)
    return nothing
end

samples(::SignalHeader) = Vector{Int16}()
samples(::AnnotationListHeader) = Vector{DataRecord}()

function read_record_annotation(io::IO)
    sign = read_sign(io)
    offset = sign * parse(Float64, String(readuntil(io, 0x14)))
    if Base.peek(io) !== 0x0
        events = read_events(io)
    else
        events = nothing
        Base.skip(io, 1)
    end
    return RecordAnnotation(offset, events)
end

function read_timestamp_annotation(io::IO)
    sign = read_sign(io)
    raw = readuntil(io, 0x14)
    timestamp = split(String(raw), '\x15'; keepempty=false)
    offset = sign * parse(Float64, popfirst!(timestamp))
    if isempty(timestamp)
        duration = nothing
    else
        duration = parse(Float64, popfirst!(timestamp))
    end
    events = read_events(io)
    events !== nothing || error("No events found for timestamp annotation at offset $offset")
    return TimestampAnnotation(offset, duration, events)
end

function read_sign(io::IO)
    sign = Base.read(io, UInt8)
    sign === 0x2b || sign === 0x2d || error("Starting byte of annotation must be '+' or '-'.")
    return sign === 0x2b ? 1 : -1
end

function read_events(io::IO)
    raw = readuntil(io, 0x0)
    events = split(String(raw), '\x14'; keepempty=false)
    events = convert(Vector{String}, events)
    return isempty(events) ? nothing : events
end

"""
    EDF.read(file::AbstractString)

Read the given file and return an `EDF.File` object containing the parsed data.
"""
function read(file::AbstractString)
    open(file, "r") do io
        file_header, signal_headers = read_file_and_signal_headers(io)
        signals, annotations = read_signals(io, file_header, signal_headers)
        return File(file_header, signals, annotations)
    end
end
