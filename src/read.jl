#####
##### Parsing utilities
#####

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

function read_header(io::IO, extended::Bool=true)
    version = strip(String(read(io, 8)))

    patient_id_raw = strip(String(read(io, 80)))
    patient_id = something(tryparse(PatientID, patient_id_raw), patient_id_raw)

    recording_id_raw = strip(String(read(io, 80)))
    recording_id = something(tryparse(RecordingID, recording_id_raw), recording_id_raw)

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
    if extended
        continuous = !startswith(String(read(io, 44)), "EDF+D")
    else
        continuous = true  # Records are always continuous per original EDF spec
        skip(io, 44)  # Reserved
    end
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

    @assert position(io) == nb_header

    h = EDFHeader(version, patient_id, recording_id, continuous, start, n_records,
                  duration, n_signals, nb_header)
    return (h, signals)
end

function read_data!(io::IO, signals::Vector{Signal}, header::EDFHeader)
    nrecs = header.n_records
    nsigs = header.n_signals
    for sig in signals
        sig.samples = Vector{Int16}()
    end
    for i = 1:nrecs, j = 1:nsigs
        data = reinterpret(Int16, read(io, 2 * signals[j].n_samples))
        append!(signals[j].samples, data)
    end
    @assert eof(io)
    return signals
end
