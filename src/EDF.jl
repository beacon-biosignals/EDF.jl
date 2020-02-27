module EDF

using Dates

#####
##### Types
#####

"""
    EDF.PatientID

Type representing the local patient identification field of an EDF header, assuming the
file is EDF+ compliant.
`EDF.File`s which are parsed from files which are not EDF+ compliant do not contain this
type; the corresponding field is instead a `String`.

# Fields

* `code` (`String` or `Missing`): The code by which a patient is referred, if known
* `sex` (`Char` or `Missing`): Patient sex, `'M'`, `'F'`, or `missing` if unknown
* `birthdate` (`Date` or `Missing`): Patient date of birth, if known
* `name` (`String` or `Missing`): Patient name, if known
"""
struct PatientID
    code::Union{String,Missing}
    sex::Union{Char,Missing}
    birthdate::Union{Date,Missing}
    name::Union{String,Missing}
end

"""
    EDF.RecordingID

Type representing the local recording identification field of an EDF header, assuming
the file is EDF+ compliant.
`EDF.File`s which are parsed from files which are not EDF+ compliant do not contain
this type; the corresponding field is instead a `String`.

# Fields

* `startdate` (`Date` or `Missing`): Start date of the recording
* `admincode` (`String` or `Missing`): Administration code for the recording
* `technician` (`String` or `Missing`): Identifier for the technician or investigator
* `equipment` (`String` or `Missing`): Identifier for the equipment used
"""
struct RecordingID
    startdate::Union{Date,Missing}
    admincode::Union{String,Missing}
    technician::Union{String,Missing}
    equipment::Union{String,Missing}
end

"""
    EDF.AnnotationsList

Type representing a time-stamp annotations list (TAL).

# Fields

* `offset` (`Float64`): Offset from the recording start time (specified in the header)
  at which the event in this TAL starts
* `duration` (`Float64` or `Nothing`): Duration of the event, if specified
* `event` (`Vector{String}`): List of events for this TAL
"""
struct AnnotationsList
    offset::Float64
    duration::Union{Float64,Nothing}
    event::Vector{String}
end

"""
    EDF.RecordAnnotation

Type containing all annotations applied to a particular data record.

# Fields

* `offset` (`Float64`): Offset from the recording start time (specified in the header)
  at which the current data record starts
* `event` (`Vector{String}` or `Nothing`): The event that marks the start of the data
  record, if applicable
* `annotations` (`Vector{EDF.AnnotationsList}`): The time-stamped annotations lists (TALs)
  in the current data record
* `n_bytes` (`Int`): The number of raw bytes per data record in the "EDF Annotation" signal
"""
mutable struct RecordAnnotation
    offset::Float64
    event::Union{Vector{String},Nothing}
    annotations::Vector{AnnotationsList}
    n_bytes::Int

    RecordAnnotation() = new()
    RecordAnnotation(offset, event, annotations, n_bytes) = new(offset, event, annotations, n_bytes)
end

"""
    EDF.FileHeader

Type representing the header record for an EDF file.

## Fields

* `version` (`String`): Version of the data format
* `patient` (`String` or `EDF.PatientID`): Local patient identification
* `recording` (`String` or `EDF.RecordingID`): Local recording identification
* `continuous` (`Bool`): If true, data records are contiguous. This field defaults to `true` for files that are EDF-compliant but not EDF+-compliant.
* `start` (`DateTime`): Date and time the recording started
* `n_records` (`Int`): Number of data records
* `duration` (`Float64`): Duration of a data record in seconds
* `n_signals` (`Int`): Number of signals in a data record
"""
struct FileHeader
    version::String
    patient::Union{String,PatientID}
    recording::Union{String,RecordingID}
    continuous::Bool
    start::DateTime
    n_records::Int
    duration::Float64
    n_signals::Int
end

mutable struct SignalHeader
    label::String
    transducer::String
    physical_units::String
    physical_min::Float32
    physical_max::Float32
    digital_min::Float32
    digital_max::Float32
    prefilter::String
    n_samples::Int16

    SignalHeader() = new()
end

# TODO: Make the vector of samples mmappable
# Also TODO: Refactor to make signals immutable
"""
    EDF.Signal

Type representing a single signal extracted from an EDF file.

# Fields

* `label` (`String`): The name of the signal, e.g. `F3-M2`
* `transducer` (`String`): Transducer type
* `physical_units` (`String`): Units of measure for the signal, e.g. `uV`
* `physical_min` (`Float32`): The physical minimum value of the signal
* `physical_max` (`Float32`): The physical maximum value of the signal
* `digital_min` (`Float32`): The minimum value of the signal that could occur in a data record
* `digital_max` (`Float32`): The maximum value of the signal that could occur in a data record
* `prefilter` (`String`): Description of any prefiltering done to the signal
* `n_samples` (`Int16`): The number of samples in a data record (NOT overall)
* `samples` (`Vector{Int16}`): The encoded sample values of the signal

!!! note
    Samples are stored in a `Signal` object in the same encoding as they appear in raw
    EDF files. See [`decode`](@ref) for decoding signals to their physical values.
"""
mutable struct Signal
    header::SignalHeader
    samples::Vector{Int16}

    Signal() = new()
end

"""
    EDF.File

Type representing a parsed EDF file.
All data defined in the file is accessible from this type by inspecting its fields
and the fields of the types of those fields.

# Fields

* `header` (`EDF.FileHeader`): File-level metadata extracted from the file header
* `signals` (`Vector{EDF.Signal}`): All signals extracted from the data records
* `annotations` (`Vector{EDF.RecordAnnotation}` or `Nothing`): A vector of length
  `header.n_records` where each element contains annotations for the corresponding
  data record, if annotations are present in the file
"""
struct File
    header::FileHeader
    signals::Vector{Signal}
    annotations::Union{Vector{RecordAnnotation},Nothing}
end

function Base.show(io::IO, edf::File)
    print(io, "EDF.File with ", length(edf.signals), " signals")
end

#####
##### Utilities
#####

"""
    EDF.decode(signal::Signal)

Decode the sample values in the given signal and return a `Vector` of the physical values.
"""
function decode(signal::Signal)
    digital_range = signal.header.digital_max - signal.header.digital_min
    physical_range = signal.header.physical_max - signal.header.physical_min
    return @. ((signal.samples - signal.header.digital_min) / digital_range) * physical_range + signal.header.physical_min
end

#####
##### The rest
#####

include("read.jl")
include("write.jl")

end # module
