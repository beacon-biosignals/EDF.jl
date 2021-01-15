#####
##### `EDF.Signal`
#####

const SIGNAL_HEADER_FIELDS = [(:label, 16),
                              (:transducer_type, 80),
                              (:physical_dimension, 8),
                              (:physical_minimum, 8),
                              (:physical_maximum, 8),
                              (:digital_minimum, 8),
                              (:digital_maximum, 8),
                              (:prefilter, 80),
                              (:samples_per_record, 8)]

"""
    EDF.SignalHeader

Type representing the header for a single EDF signal.

# Fields

* `label::String`: the signal's type/sensor label, see https://www.edfplus.info/specs/edftexts.html#label
* `transducer_type::String`: non-standardized transducer type information
* `physical_dimension::String`: see https://www.edfplus.info/specs/edftexts.html#physidim
* `physical_minimum::Float32`: physical minimum value of the signal
* `physical_maximum::Float32`: physical maximum value of the signal
* `digital_minimum::Float32`: minimum value of the signal that could occur in a data record
* `digital_maximum::Float32`: maximum value of the signal that could occur in a data record
* `prefilter::String`: non-standardized prefiltering information
* `samples_per_record::Int16`: number of samples in a data record (NOT overall)
"""
struct SignalHeader
    label::String
    transducer_type::String
    physical_dimension::String
    physical_minimum::Float32
    physical_maximum::Float32
    digital_minimum::Float32
    digital_maximum::Float32
    prefilter::String
    samples_per_record::Int16
end

"""
    EDF.Signal

Type representing a single EDF signal.

# Fields

* `header::SignalHeader`
* `samples::Vector{Int16}`
"""
struct Signal
    header::SignalHeader
    samples::Vector{Int16}
end

Signal(header::SignalHeader) = Signal(header, Int16[])

"""
    EDF.decode(signal::Signal)

Return `signal.samples` decoded into the physical units specified by `signal.header`.
"""
function decode(signal::Signal)
    dmin, dmax = signal.header.digital_minimum, signal.header.digital_maximum
    pmin, pmax = signal.header.physical_minimum, signal.header.physical_maximum
    return @. ((signal.samples - dmin) / (dmax - dmin)) * (pmax - pmin) + pmin
end

SignalHeader(signal::Signal) = signal.header

#####
##### `EDF.AnnotationsSignal`
#####

const ANNOTATIONS_SIGNAL_LABEL = "EDF Annotations"

"""
    EDF.TimestampedAnnotationList

A type representing a time-stamped annotations list (TAL).

Note that this type's constructor may attempt to round given `onset_in_seconds` and
`duration_in_seconds` arguments to their nearest representable values in accordance
with the EDF+ specification, which a) represents these values as ASCII, b) constrains
these values to an 8 character limit, and c) does not allow the use of scientific
notation for these fields.

See EDF+ specification for details.

# Fields

* `onset_in_seconds::Float64`: onset w.r.t. recording start time (may be negative)
* `duration_in_seconds::Union{Float64,Nothing}`: duration of this TAL
* `annotations::Vector{String}`: the annotations associated with this TAL
"""
struct TimestampedAnnotationList
    onset_in_seconds::Float64
    duration_in_seconds::Union{Float64,Nothing}
    annotations::Vector{String}
    function TimestampedAnnotationList(onset_in_seconds, duration_in_seconds, annotations)
        onset_in_seconds = _nearest_representable_edf_time_value(onset_in_seconds)
        duration_in_seconds = _nearest_representable_edf_time_value(duration_in_seconds)
        return new(onset_in_seconds, duration_in_seconds, annotations)
    end
end

_nearest_representable_edf_time_value(::Nothing) = nothing

function _nearest_representable_edf_time_value(x)
    return round(x; digits=(8 - (ndigits(floor(Int, x)) + signbit(x) + isinteger(x))))
end

function Base.:(==)(a::TimestampedAnnotationList, b::TimestampedAnnotationList)
    return a.onset_in_seconds == b.onset_in_seconds &&
           a.duration_in_seconds == b.duration_in_seconds &&
           a.annotations == b.annotations
end

"""
    EDF.AnnotationsSignal

Type representing a single EDF Annotations signal.

# Fields

* `samples_per_record::Int16`
* `records::Vector{Vector{TimestampedAnnotationList}}`
"""
struct AnnotationsSignal
    samples_per_record::Int16
    records::Vector{Vector{TimestampedAnnotationList}}
end

function AnnotationsSignal(header::SignalHeader)
    records = Vector{TimestampedAnnotationList}[]
    return AnnotationsSignal(header.samples_per_record, records)
end

"""
    AnnotationsSignal(records::Vector{Vector{TimestampedAnnotationList}})

Return `AnnotationsSignal(samples_per_record, records)` where `samples_per_record`
is the minimum value required to write out each record completely (i.e. the maximum
required `samples_per_record` across all records).
"""
function AnnotationsSignal(records::Vector{Vector{TimestampedAnnotationList}})
    # Actually writing out the TALs in order to calculate the minimum necessary
    # `samples_per_record` is super wasteful from a performance perspective, but
    # is at least robust/self-consistent with the rest of the package. In theory
    # we shouldn't even store this value, and rather always compute it on write,
    # but cleanly refactoring the package to do this would be a more involved
    # change than is meritted at the moment (since normal signals are already
    # treated similarly, i.e. the `SignalHeader` is overly trusted).
    max_bytes_per_record = maximum(sum(write_tal(IOBuffer(), tal) for tal in record) for record in records)
    return AnnotationsSignal(Int16(cld(max_bytes_per_record, 2)), records)
end

function SignalHeader(signal::AnnotationsSignal)
    return SignalHeader("EDF Annotations", "", "", -1, 1, -32768, 32767,
                        "", signal.samples_per_record)
end

#####
##### EDF+ Patient/Recording Metadata
#####

"""
    EDF.PatientID

A type representing the local patient identification field of an EDF+ header.

See EDF+ specification for details.

# Fields

* `code::Union{String,Missing}`
* `sex::Union{Char,Missing}` (`'M'`, `'F'`, or `missing`)
* `birthdate::Union{Date,Missing}`
* `name::Union{String,Missing}`
"""
struct PatientID
    code::Union{String,Missing}
    sex::Union{Char,Missing}
    birthdate::Union{Date,Missing}
    name::Union{String,Missing}
end

"""
    EDF.RecordingID

A type representing the local recording identification field of an EDF+ header.

See EDF+ specification for details.

# Fields

* `startdate::Union{Date,Missing}`
* `admincode::Union{String,Missing}`
* `technician::Union{String,Missing}`
* `equipment::Union{String,Missing}`
"""
struct RecordingID
    startdate::Union{Date,Missing}
    admincode::Union{String,Missing}
    technician::Union{String,Missing}
    equipment::Union{String,Missing}
end

#####
##### `EDF.File`
#####

const BYTES_PER_FILE_HEADER = 256

const BYTES_PER_SIGNAL_HEADER = 256

"""
    EDF.FileHeader

Type representing the parsed header record of an `EDF.File` (excluding signal headers).

# Fields

* `version::String`: data format version
* `patient::Union{String,PatientID}`: local patient identification
* `recording::Union{String,RecordingID}`: local recording identification
* `start::DateTime`: start date/time of the recording
* `is_contiguous::Bool`: if `true`, data records are contiguous; is `true` for non-EDF+-compliant files
* `record_count::Int`: number of data records in the recording
* `seconds_per_record::Float64`: duration of a data record in seconds
"""
struct FileHeader
    version::String
    patient::Union{String,PatientID}
    recording::Union{String,RecordingID}
    start::DateTime
    is_contiguous::Bool
    record_count::Int
    seconds_per_record::Float64
end

"""
    EDF.File{I<:IO}

Type representing an EDF file.

# Fields

* `io::I`
* `header::FileHeader`
* `signals::Vector{Union{Signal,AnnotationsSignal}}`
"""
struct File{I<:IO}
    io::I
    header::FileHeader
    signals::Vector{Union{Signal,AnnotationsSignal}}
end

function Base.show(io::IO, edf::File)
    print(io, "EDF.File with ", length(edf.signals), " signals")
end

Base.close(file::File) = close(file.io)
