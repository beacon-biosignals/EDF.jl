# EDF.jl

EDF.jl is a Julia package for working with [European Data Format (EDF)](https://edfplus.info)
files, including reading, writing, and an intermediate representation for direct access
to data.

## Package API

```@meta
CurrentModule = EDF
```
### Representation of Data

EDF files consist of a header record, which contains file-level metadata, and a number
of contiguous data records, each containing a chunk of each signal.
In Julia, we represent this with an `EDF.File` type that consists of an `EDF.Header`
object and a vector of `EDF.Signal`s.

```@docs
EDF.File
EDF.FileHeader
EDF.SignalHeader
EDF.AnnotationList
EDF.AnnotationListHeader
EDF.AbstractAnnotation
EDF.RecordAnnotation
EDF.TimestampAnnotation
EDF.TimestampAnnotationList
EDF.DataRecord
EDF.PatientID
EDF.RecordingID
```

Per the original EDF specification, the signals are assumed to be continuous across data
records.
However, the EDF+ specification introduced the notion of discontinuous signals, denoted
with a value of "EDF+D" in one of the reserved fields.
The `EDF.Header` type notes this in a `Bool` field called `continuous`.
The signal data is always stored contiguously, regardless of whether the data records are
declared to be continuous, but, given an `EDF.Signal` object and its associated sample values,
users of the package can divide the signal by records if needed using

```julia
signal, samples = first(edf.signals)
Iterators.partition(samples, signal.n_samples)
```

This will construct a lazy iterator over non-overlapping chunks of the signal, iterating
which yields a total of `header.n_records` items.

### Reading

```@docs
EDF.open
EDF.read
EDF.read!
EDF.decode
```

### Writing

```@docs
EDF.write
```
