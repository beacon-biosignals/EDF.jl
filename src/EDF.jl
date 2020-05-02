module EDF

using Dates

#####
##### `EDF.Signal`
#####
# TODO canonicalized label parsing

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

#####
##### `EDF.AnnotationsSignal`
#####

"""
    EDF.AnnotationsSignalHeader

Type representing the header for a single EDF Annotations signal.

# Fields

* `samples_per_record::Int16`: number of samples in a data record (NOT overall)
* `original_index::Int`: the original index of the annotations signal in the EDF file's
  list of signals (this is a "bookkeeping index" for use by EDF.jl, and is not part of
  the actual EDF/EDF+ specification)
"""
struct AnnotationsSignalHeader
    samples_per_record::Int16
    original_index::Int
end

"""
    EDF.AnnotationsSignal

Type representing a single EDF Annotations signal.

# Fields

* `header::AnnotationsSignalHeader`
* `records::Vector{Vector{TimestampedAnnotationList}}`
"""
struct AnnotationsSignal
    header::AnnotationsSignalHeader
    records::Vector{Vector{TimestampedAnnotationList}}
end

"""
    EDF.TimestampedAnnotationList <: EDF.AbstractAnnotation

A type representing a time-stamped annotations list (TAL).

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
end

# TODO replace with convert methods
# function AnnotationsSignalHeader(header::SignalHeader, offset::Int)
#     return AnnotationsSignalHeader(header.n_samples, offset)
# end
# function SignalHeader(header::AnnotationsSignalHeader)
#     return SignalHeader("EDF Annotations", "", "", -1, 1, -32768, 32767,
#                         "", header.samples_per_record)
# end

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
##### EDF+ Annotations
#####

"""
    EDF.TimestampAnnotation <: EDF.AbstractAnnotation

A type representing an element of a time-stamp annotations list (TAL).

See EDF+ specification for details.

# Fields

* `onset_in_seconds::Float64`: onset w.r.t. recording start time (may be negative)
* `duration_in_seconds::Union{Float64,Nothing}`: duration of this TAL annotation
* `events::Vector{String}`: list of events associated with this TAL annotation
"""
struct TimestampAnnotation <: AbstractAnnotation
    offset_in_seconds::Float64
    duration_in_seconds::Union{Float64,Nothing}
    events::Vector{String}
end

# """
#     EDF.AbstractAnnotation
#
# An abstract type representing an EDF+ annotation.
# """
# abstract type AbstractAnnotation end
#
# """
#     EDF.TimestampAnnotation <: EDF.AbstractAnnotation
#
# A type representing an element of a time-stamp annotations list (TAL).
#
# See EDF+ specification for details.
#
# # Fields
#
# * `offset_in_seconds::Float64`: offset from recording start time
# * `duration_in_seconds::Union{Float64,Nothing}`: duration of this TAL
# * `events::Vector{String}`: list of TAL e
#
# * `offset_in_seconds` (`Float64`): Offset from the recording start time (specified in the header)
#   at which the event in this TAL starts
# * `duration_in_seconds` (`Float64` or `Nothing`): Duration of the event, if specified
# * `events` (`Vector{String}`): List of events for this TAL
# """
# struct TimestampAnnotation <: AbstractAnnotation
#     offset_in_seconds::Float64
#     duration_in_seconds::Union{Float64,Nothing}
#     events::Vector{String}
# end
#
# """
#     EDF.RecordAnnotation <: EDF.AbstractAnnotation
#
# A type representing a record-level annotation in an `EDF.File`.
#
# # Fields
#
# * `offset` (`Float64`): Offset from the recording start time (specified in the header)
#   at which the current data record starts
# * `events` (`Vector{String}` or `Nothing`): The events that mark the start of the data
#   record, if applicable
# """
# struct RecordAnnotation <: AbstractAnnotation
#     offset::Float64
#     events::Union{Vector{String},Nothing}
# end
#
# """
#     EDF.TimestampAnnotationList
#
# An alias for a list of `TimestampAnnotation`s, if present, in a `DataRecord`.
# """
# const TimestampAnnotationList = Union{Vector{TimestampAnnotation},Nothing}
#
# """
#     EDF.DataRecord
#
# A representation of all annotation information in an EDF+ data record.
# """
# const DataRecord = Pair{RecordAnnotation,TimestampAnnotationList}
#
#
#
# """
#     EDF.AnnotationListHeader
#
# Type representing the header record for an `AnnotationList`
#
# # Fields
#
# * `n_samples` (`Int16`): The number of samples in a single data record
# * `offset_in_file` (`Int`): The annotation header's position,
#    relative to other signals in its origin file
# """
# struct AnnotationListHeader
#     n_samples::Int16
#     offset_in_file::Int
# end
#
# function AnnotationListHeader(header::SignalHeader, offset::Int)
#     return AnnotationListHeader(header.n_samples, offset)
# end
#
# function SignalHeader(header::AnnotationListHeader)
#     return SignalHeader("EDF Annotations", "", "", -1, 1, -32768, 32767, "", header.n_samples)
# end
#
# """
#     EDF.AnnotationList
#
# Type representing a single signal extracted from an EDF file.
#
# # Fields
#
# * `header` (`AnnotationListHeader`): Signal-level metadata extracted from the signal header
# * `records` (`Vector{DataRecord}`): EDF+ file annotation information on a per-record basis
# """
# struct AnnotationList
#     header::AnnotationListHeader
#     records::Vector{DataRecord}
# end

#####
##### `EDF.File`
#####

"""
    EDF.FileHeader

Type representing file-wide metadata for an EDF `File`.

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
    EDF.File{C<:IO}

Type representing an EDF file's metadata.
To access the sample data for a signal in `signals`

# Fields

* `io` (`C<:IO`): The IO source for the EDF file.
* `header` (`FileHeader`): File-level metadata extracted from the file header
* `signals` (`Vector{Pair{SignalHeader,Vector{Int16}}}`): A `Vector` of `Pair`s, where
   the first item in each pair contains signal-level metadata for the signal's
   samples, and the second item contains the encoded sample values for that signal
* `annotations` (`AnnotationList` or `Nothing`): If specified, a list of EDF+ Annotations
"""
struct File{C<:IO}
    io::C
    header::FileHeader
    signals::Vector{Signal}
    annotations::Union{AnnotationsSignal,Nothing}
end

function Base.show(io::IO, edf::File)
    print(io, "EDF.File with ", length(edf.signals), " signals")
end

Base.close(file::File) = close(file.io)

#####
##### Utilities
#####

"""
    EDF.decode(signal::Signal)

Decode the data in `samples` using `samples.signal` and return a `Vector` of the physical values.
"""
function decode((signal, samples)::Pair{SignalHeader,Vector{Int16}})
    digital_range = signal.digital_max - signal.digital_min
    physical_range = signal.physical_max - signal.physical_min
    return @. ((samples - signal.digital_min) / digital_range) * physical_range + signal.physical_min
end

#####
##### I/O
#####

const SIGNAL_HEADER_BYTES = (16, 80, 8, 8, 8, 8, 8, 80, 8)

include("read.jl")
include("write.jl")

end # module
