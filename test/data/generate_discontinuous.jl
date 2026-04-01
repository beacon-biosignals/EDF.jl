using Luna_jll

luna() do exec
    run(pipeline(`$exec test.edf -s WRITE edf-tag=vanilla force-edf`))
    run(pipeline(`$exec test-vanilla.edf starttime=10.19.44 -s 'SET-HEADERS start-time=10.19.44 & WRITE edf-tag=2'`))
    return run(pipeline(`$exec --merge test-vanilla.edf test-vanilla-2.edf edf=test_merged.edf `))
end
