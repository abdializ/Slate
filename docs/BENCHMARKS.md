# Tab workspace benchmark

Slate's intended advantage is resource-conscious tab lifecycle. This benchmark checks two separate questions: the cost of keeping 24 pages loaded, and the cost of restoring 24 saved Slate tabs while loading only the selected page. It also checks continuity and synchronous activation when switching between loaded split and single-tab workspaces.

## Results — 2026-10-05

Test machine: Apple M3 Pro, 18 GiB RAM, macOS 27.0. Chrome 154.0.8037.95. Slate Release verification build at [`3acf62b`](https://github.com/abdializ/Slate/commit/3acf62b73bd7e890143736d7012ab123fed3455a). Binary, fixture, and runner hashes plus every accepted sample are in the [sanitized results](benchmarks/2026-10-05-tabs.json).

Each figure below is the median of the three run medians. Each run median uses three accepted samples. Ranges show the lowest and highest run medians, not confidence intervals.

| Browser and condition | Logical tabs | Loaded pages | Footprint median (MiB) | Run-median range (MiB) | Processes per sample |
| --- | ---: | ---: | ---: | ---: | ---: |
| Slate: saved workspace | 24 | 1 | 233.8 | 141.4–241.7 | 4 |
| Chrome: one-page baseline | 1 | 1 | 692.5 | 675.3–693.8 | 12 |
| Slate: fully loaded workspace | 24 | 24 | 1,194.2 | 1,074.2–1,556.0 | 27 |
| Chrome: fully loaded workspace | 24 | 24 | 1,628.9 | 1,573.2–1,653.3 | 34–36 |

In this specific fully loaded workload, Slate's median group footprint was about **27% lower** than Chrome's. Slate also varied substantially between runs: its first loaded run was close to Chrome's. These measurements are initial evidence for this fixture, not a general claim about real websites, Chrome Memory Saver, energy use, or every browser. The lazy condition uses about **80% less** footprint than Slate's fully loaded condition, but has only one running page. It must not be presented as a matched 24-loaded-page comparison.

Across the three Slate runs, **90/90 loaded-workspace checks passed**, with existing WebKit views reused and no extra navigations. Both split pages retained their edited fields and JavaScript state in every run. Synchronous native activation plus validation had a median of **4.24 ms**, a 95th percentile of **9.35 ms**, and a maximum of **9.79 ms**. These timings exclude subsequent painting and display scanout.

For the 69 on-demand Slate fixture loads, server request-to-ready time was median **18.46 ms**, 95th percentile **22.92 ms**, maximum **25.03 ms**. This excludes selection and engine creation before the HTTP request and is not a claim that a real unloaded website restores in 18 ms. Chrome opened the 23 additional pages concurrently; Slate selected them sequentially, so those loading distributions are not a matched speed comparison. Launch-to-first-fixture timings are recorded in the JSON but are not used as a product speed claim.

All 18 fully loaded samples recorded warning pressure. Across all 36 accepted samples, 33 recorded warning and three normal pressure. Other applications remained running; the runner did not induce pressure. Two Chrome loaded-condition samples needed a second attempt after their target process set changed. One Slate trial was rerun after the loaded-page count changed during lazy-condition sampling; the cause was not established, and that trial was excluded. Only the complete validated trials above contribute to the results.

The next measurement should use mixed origins, representative real pages, longer sessions, matched restore policies, and controlled foreground/idle conditions. Automatic unloading should be evaluated only after the page-protection contract is complete.

## Reproduce

Requirements: macOS on Apple Silicon, Python 3, CMake, Google Chrome, and permission to inspect your own processes with macOS `footprint`. No root access is needed. Use a verification-enabled **Release** build:

```sh
cmake -S . -B build-benchmark -DCMAKE_BUILD_TYPE=Release -DSLATE_ENABLE_VERIFY=ON
cmake --build build-benchmark -j 4
python3 scripts/benchmark_tabs.py \
  --slate-app build-benchmark/platform/macos/Slate.app \
  --output benchmark-results.json
```

The runner creates fresh temporary Slate and Chrome profiles. Slate runs from a temporary app copy with a unique bundle identifier so its WebKit helpers can be attributed to that instance. Chrome uses a separate user-data directory. Cleanup targets the test instances; it does not quit existing browsers or read personal browsing histories. The fixture server listens only on loopback. Published JSON contains browser versions, hardware class, process counts, numeric measurements, source/binary/fixture hashes, and synthetic fixture numbers. Raw app and footprint logs remain temporary.

`scripts/profile_memory.py` is a compatibility entry point to this runner. It accepts the same arguments and no longer deletes a fixed folder or attributes all Slate instances' WebKit helpers to one browser.

Incomplete samples are rejected and retried up to three times against a newly identified process group. Accepted samples record the attempt count. A failed run leaves an ignored `*.partial.json` checkpoint of completed trials; repeat the same command with `--resume` to continue only if the machine, versions, binary, source revision, fixture, runner, and workload match. The final JSON is written only after all trials pass.

## Workload and measurement

- 24 identical local documents at one HTTP origin, each with 1,500 DOM rows, a touched and retained 2 MiB byte array, an edited field, and JavaScript state. Each page reports completion after creating its content and forcing layout. There are no remote fonts, site requests, extensions, ads, video, or downloads in the fixture.
- Three independent runs per browser with fresh profiles, alternating Slate/Chrome order between repeats. Each condition receives four seconds to settle, then three group-footprint samples separated by one second. The verification runner waits for a measurement-complete signal before opening more pages or beginning switch checks; a fixed timer cannot overlap conditions. This is a short settled-workspace test, not a long-duration discard test.
- Chrome first loads one page, then opens the remaining 23. Slate begins with 24 saved logical tabs and one selected page, then selects the other 23 to load all 24. The server must receive all expected completion callbacks; incomplete runs fail instead of publishing partial results.
- The fully loaded comparison has the same logical-tab and loaded-page counts. Slate's lazy condition is reported separately; Chrome's one-page baseline has only one logical tab. Comparing those conditions does not prove superiority over Chrome session restoration or Memory Saver.
- The memory metric is the `total footprint` from **one** `/usr/bin/footprint` invocation targeting the complete identified process group, converted to MiB (1,048,576 bytes). Both apps launch through LaunchServices into their own macOS coalitions. Chrome includes its descendants and Chrome app helpers sharing both coalition IDs. Slate includes its descendants and WebKit helpers sharing both coalition IDs. This follows Apple's [process coalition structure](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info_private.h). The runner rejects absent helpers, omitted target processes, zero values, and footprint errors. It does not add RSS values and call the sum unique physical memory.
- macOS physical footprint is an accounting metric with shared/compressed-memory effects; it is not total machine RAM or a direct energy measurement. System pressure levels are recorded with each sample (1 normal, 2 warning, 4 critical). Other applications remain running, so this is not an otherwise idle laboratory machine. No artificial memory pressure is applied.
- Each Slate run performs 30 loaded-workspace checks between a split pair and a single tab. Checks verify hit-test visibility, reuse of the existing WebKit views, no additional navigation, and survival of the pair's edited fields and JavaScript state. Timings cover synchronous native activation and validation. They exclude subsequent compositing, paint completion, and display scanout, and have no Chrome switching comparison.
- Local request-to-ready timings start when the fixture server receives the page request and end when it receives the page's completion callback. They exclude the preceding selection and process-launch work. They are not end-to-end restore latency or real-site load predictions. First-fixture startup timings are approximate, include LaunchServices dispatch and process startup, and use polling with 100 ms resolution.

## Limits

This same-origin synthetic workload favors renderer sharing where an engine supports it. It does not represent a mixed set of independent sites or streaming services. The engines also differ: Slate uses the system WebKit with its own instrumentation and bundled local filters; Chrome uses Chromium with fresh-profile defaults. No protections or security features are disabled to equalize them.

These results cannot establish an advantage across all browsers, websites, Macs, or memory-pressure conditions. Safari is not included: an existing personal session was running, and the runner does not alter it. Battery life, CPU use, sustained idle behavior, memory under induced pressure, automatic unloading, real streaming ads, and end-to-end visual latency remain unmeasured. Manual unload reloads the URL on restoration and can lose page state. Automatic unloading remains disabled.
