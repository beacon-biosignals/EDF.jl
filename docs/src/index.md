# EDF.jl

EDF.jl is a Julia package for working with [European Data Format (EDF)](https://edfplus.info)
and [BioSemi Data Format (BDF)](https://www.biosemi.com/faq/file_format.htm) files,
including reading, writing, and an intermediate representation for direct access to data.

## Package API

```@meta
CurrentModule = EDF
```
### Representation of Data

```@docs
EDF.File
EDF.FileHeader
EDF.SignalHeader
EDF.Signal
EDF.AnnotationsSignal
EDF.TimestampedAnnotationList
EDF.PatientID
EDF.RecordingID
EDF.sample_type
EDF.is_bdf
```

The EDF+ specification introduced the notion of discontiguous signals, denoted with a value of "EDF+D" in one of the reserved fields; the `EDF.FileHeader` type notes this in a `Bool` field called `is_contiguous`. EDF.jl always *stores* signal data contiguously, regardless of whether the data records are declared to be contiguous, but, given an `EDF.Signal`, users of the package can construct a lazy iterator over non-overlapping chunks of a `signal::EDF.Signal` via:

```julia
Iterators.partition(signal.samples, signal.header.samples_per_record)
```

### Reading

```@docs
EDF.read
EDF.read!
EDF.decode
```

### Writing

```@docs
EDF.write
```
