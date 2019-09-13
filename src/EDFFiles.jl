module EDFFiles

export EDFFile, Signal, PatientID, RecordingID, write_edf

using Dates

#####
##### Types
#####

struct PatientID
    code::Union{String,Missing}
    sex::Union{Char,Missing}
    birthdate::Union{Date,Missing}
    name::Union{String,Missing}
end

struct RecordingID
    startdate::Union{Date,Missing}
    admincode::Union{String,Missing}
    technician::Union{String,Missing}
    equipment::Union{String,Missing}
end

"""
    EDFHeader

Type representing the header record for an EDF file.

## Fields

* `version` (`String`): Version of the data format
* `patient` (`String` or `PatientID`): Local patient identification
* `recording` (`String` or `RecordingID`): Local recording identification
* `start` (`DateTime`): Date and time the recording started
* `n_records` (`Int`): Number of data records
* `duration` (`Float64`): Duration of a data record in seconds
* `n_signals` (`Int`): Number of signals in a data record
* `nb_header` (`Int`): Total number of raw bytes in the header record
"""
struct EDFHeader
    version::String
    patient::Union{String,PatientID}
    recording::Union{String,RecordingID}
    continuous::Bool
    start::DateTime
    n_records::Int
    duration::Float64
    n_signals::Int
    nb_header::Int
end

# TODO: Make the vector of samples mmappable
# Also TODO: Refactor to make signals immutable
"""
    Signal

Type representing a single signal extracted from an EDF file.

# Fields

* `label` (`String`): The name of the signal, e.g. `F3-M2`
* `transducer` (`String`): Transducer type
* `physical_units` (`String`): Units of measure for the signal, e.g. `uV`
* `physical_min` (`Int16`): The physical minimum value of the signal
* `physical_max` (`Int16`): The physical maximum value of the signal
* `digital_min` (`Int16`): The minimum value of the signal that could occur in a data record
* `digital_max` (`Int16`): The maximum value of the signal that could occur in a data record
* `prefilter` (`String`): Description of any prefiltering done to the signal
* `n_samples` (`Int16`): The number of samples in a data record (NOT overall)
* `samples` (`Vector{Int16}`): The sample values of the signal
"""
mutable struct Signal
    label::String
    transducer::String
    physical_units::String
    physical_min::Int16
    physical_max::Int16
    digital_min::Int16
    digital_max::Int16
    prefilter::String
    n_samples::Int16
    samples::Vector{Int16}

    Signal() = new()
end

"""
    EDFFile

Type representing a parsed EDF file.
All data defined in the file is accessible from this type by inspecting its fields
and the fields of the types of those fields.

# Fields

* `header` (`EDFHeader`): File-level metadata extracted from the file header
* `signals` (`Vector{Signal}`): All signals extracted from the data records
"""
struct EDFFile
    header::EDFHeader
    signals::Vector{Signal}
end

function EDFFile(file::AbstractString)
    open(file, "r") do io
        header, data = read_header(io)
        read_data!(io, data, header)
        EDFFile(header, data)
    end
end

function Base.show(io::IO, edf::EDFFile)
    print(io, "EDFFile with ", length(edf.signals), " signals")
end

#####
##### The rest
#####

include("read.jl")
include("write.jl")

end # module
