module EDFFiles

export EDFFile, Signal, PatientID, RecordingID, write_edf

using Dates

#####
##### Signals
#####

# TODO: Make the vector of samples mmappable
# Also TODO: Refactor to make signals immutable
"""
    Signal

Type representing a single signal extracted from an EDF file.
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

struct PatientID
    code::Union{String,Missing}
    sex::Union{Char,Missing}
    birthdate::Union{Date,Missing}
    name::Union{String,Missing}
end

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

struct RecordingID
    startdate::Union{Date,Missing}
    admincode::Union{String,Missing}
    technician::Union{String,Missing}
    equipment::Union{String,Missing}
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

"""
    EDFFile

Type representing a parsed EDF file.
All data defined in the file is accessible from this type through various mechanisms.
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
