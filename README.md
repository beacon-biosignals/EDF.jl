# EDF.jl

[![Build Status](https://www.travis-ci.com/beacon-biosignals/EDF.jl.svg?token=yHqDPFFPaiyJdiugxHd4&branch=master)](https://www.travis-ci.com/beacon-biosignals/EDF.jl)
[![codecov](https://codecov.io/gh/beacon-biosignals/EDF.jl/branch/master/graph/badge.svg?token=E8vy5nZtJF)](https://codecov.io/gh/beacon-biosignals/EDF.jl)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://beacon-biosignals.github.io/EDF.jl/dev)

Read and write [European Data Format (EDF/EDF+)](https://www.edfplus.info/) files in Julia.

Compared to all features implied by the EDF/EDF+ specifications, this package is currently missing:

- Out-of-core data record streaming; this package (and its type representations, i.e. `EDF.Signal`) generally assumes the user is loading all of a file's sample data into memory at once.
- Specialization for discontinuous EDF+ files ("EDF+D" files).
- Validation/specialization w.r.t. ["canonical/standard EDF texts"](https://www.edfplus.info/specs/edftexts.html)
- Support for [the EDF+ `longinteger`/`float` extension](https://www.edfplus.info/specs/edffloat.html)

Where practical, this package chooses field names that are as close to EDF/EDF+ specification terminology as possible.
