#####
##### Parsing utilities
#####

function Base.tryparse(::Type{PatientID}, raw::AbstractString)
    s = split(raw, ' ', keepempty=false)
    length(s) == 4 || return
    code_raw, sex_raw, dob_raw, name_raw = s
    length(sex_raw) == 1 || return
    code = edf_unknown(code_raw)
    sex = edf_unknown(first, sex_raw)
    dob = edf_unknown(raw->tryparse(Date, raw, dateformat"d-u-y"), dob_raw)
    dob === nothing && return
    name = edf_unknown(name_raw)
    return PatientID(code, sex, dob, name)
end

function Base.tryparse(::Type{RecordingID}, raw::AbstractString)
    s = split(raw, ' ', keepempty=false)
    length(s) == 5 || return
    first(s) == "Startdate" || return
    _, start_raw, admin_raw, tech_raw, equip_raw = s
    startdate = edf_unknown(raw->tryparse(Date, raw, dateformat"d-u-y"), start_raw)
    startdate === nothing && return
    admincode = edf_unknown(admin_raw)
    technician = edf_unknown(tech_raw)
    equipment = edf_unknown(equip_raw)
    return RecordingID(startdate, admincode, technician, equipment)
end

"""
    edf_unknown([f,] field::String)

Check whether the given text is simply "X", which per the EDF+ specification means that the
value is unknown, not applicable, or must be made anonymous, and if so return `missing`,
otherwise return the result of applying `f` to the given text. If unspecified, `f` defaults
to `identity`.
"""
edf_unknown(f, field::AbstractString) = field == "X" ? missing : f(field)
edf_unknown(field::AbstractString) = edf_unknown(identity, field)

"""
    set!(io::IO, [f=strip,] sigs::Vector{Signal}, name::Symbol, sz::Integer)

For each signal in `sigs`, set the field given by `name` to the result of `f` applied
to a chunk of size `sz` read from `io` as a `String`.
"""
function set!(io::IO, f, sigs::Vector{Signal}, name::Symbol, sz::Integer)
    n = length(sigs)
    T = fieldtype(Signal, name)
    @inbounds for i = 1:n
        x = f(String(read(io, sz)))
        setfield!(sigs[i], name, convert(T, x))
    end
    return sigs
end

function set!(io::IO, sigs::Vector{Signal}, name::Symbol, sz::Integer)
    return set!(io, strip, sigs, name, sz)
end

# TODO: Emit warning?
"""
    parse_int16(raw::String)

Attempt to parse `raw` as an `Int16`, returning 0 if the parsing fails.
"""
parse_int16(raw::AbstractString) = something(tryparse(Int16, raw), zero(Int16))

#####
##### Reading
#####

function read_header(io::IO)
    version = strip(String(read(io, 8)))

    patient_id_raw = strip(String(read(io, 80)))
    patient_id = something(tryparse(PatientID, patient_id_raw), String(patient_id_raw))

    recording_id_raw = strip(String(read(io, 80)))
    recording_id = something(tryparse(RecordingID, recording_id_raw), String(recording_id_raw))

    start_raw = read(io, 8)
    push!(start_raw, 0x20)  # Push a space separator
    append!(start_raw, read(io, 8))  # Add the time
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

    nb_header = parse(Int, String(read(io, 8)))
    reserved = String(read(io, 44))
    continuous = !startswith(reserved, "EDF+D")
    n_records = parse(Int, String(read(io, 8)))
    duration = parse(Float64, String(read(io, 8)))
    n_signals = parse(Int, String(read(io, 4)))

    signals = [Signal() for _ = 1:n_signals]

    # TODO: EDF+ allows floating point data which does not fit within the Int16 limits.
    # See https://edfplus.info/specs/edffloat.html for details. MNE seems to implement
    # this(?)

    set!(io, signals, :label, 16)
    set!(io, signals, :transducer, 80)
    set!(io, signals, :physical_units, 8)
    set!(io, parse_int16, signals, :physical_min, 8)
    set!(io, parse_int16, signals, :physical_max, 8)
    set!(io, parse_int16, signals, :digital_min, 8)
    set!(io, parse_int16, signals, :digital_max, 8)
    set!(io, signals, :prefilter, 80)
    set!(io, parse_int16, signals, :n_samples, 8)

    skip(io, 32 * n_signals)  # Reserved

    for signal in signals
        signal.samples = Vector{Int16}()  # Otherwise it's #undef
    end

    anno_idx = findfirst(signal->signal.label == "EDF Annotations", signals)
    if anno_idx !== nothing
        n_signals -= 1
    end

    @assert position(io) == nb_header

    h = EDFHeader(version, patient_id, recording_id, continuous, start, n_records,
                  duration, n_signals, nb_header)
    return (h, signals, anno_idx)
end

function read_data!(io::IO, signals::Vector{Signal}, header::EDFHeader, ::Nothing)
    for i = 1:header.n_records, signal in signals
        append!(signal.samples, reinterpret(Int16, read(io, 2 * signal.n_samples)))
    end
    @assert eof(io)
    return (signals, nothing)
end

function read_data!(io::IO, signals::Vector{Signal}, header::EDFHeader, anno_idx::Integer)
    annos = RecordAnnotation[]
    for i = 1:header.n_records
        anno = RecordAnnotation()
        anno.annotations = AnnotationsList[]
        for (j, signal) in enumerate(signals)
            n_bytes = 2 * signal.n_samples
            data = read(io, n_bytes)
            if j == anno_idx
                record = IOBuffer(data)
                while !eof(record) && Base.peek(record) != 0x0
                    toplevel, offset, duration, events = read_tal(record)
                    if toplevel
                        anno.offset = offset
                        anno.event = events
                        anno.n_bytes = n_bytes
                    else
                        push!(anno.annotations, AnnotationsList(offset, duration, events))
                    end
                end
            else
                append!(signal.samples, reinterpret(Int16, data))
            end
        end
        push!(annos, anno)
    end
    deleteat!(signals, anno_idx)
    @assert eof(io)
    return (signals, annos)
end

function read_tal(io::IO)
    c = read(io, UInt8)
    # Read the offset from the start time declared in the header
    @assert c === 0x2b || c === 0x2d  # + or -
    sign = c === 0x2b ? 1 : -1
    buffer = UInt8[]
    while true
        c = read(io, UInt8)
        if c === 0x14 || c === 0x15
            break
        end
        push!(buffer, c)
    end
    offset = sign * parse(Float64, String(buffer))
    # Read the duration, if present
    if c === 0x15
        duration = parse(Float64, String(readuntil(io, 0x14)))
    else
        duration = nothing
    end
    c = read(io, UInt8)
    record = c === 0x14  # Whether the annotation applies to the entire record
    # Read the annotation text, if present
    if c !== 0x0
        raw = readuntil(io, 0x0)
        pushfirst!(raw, c)
        events = convert(Vector{String}, split(String(raw), '\x14', keepempty=false))
    else
        events = String[]
    end
    return (record, offset, duration, events)
end
