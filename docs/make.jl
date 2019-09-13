using Documenter
using EDFFiles

makedocs(modules=[EDFFiles],
         sitename="EDFFiles.jl",
         authors="Beacon Biosignals, Inc.",
         pages=["Functionality" => "index.md"])

# Comment out until EDFFiles is open source
#deploydocs(repo="github.com/beacon-biosignals/EDFFiles.jl.git")
