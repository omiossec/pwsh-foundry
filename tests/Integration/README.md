# Integration: Foundry CLI compatibility

`Test-FoundryCompatibility.ps1` runs every PwshFoundry feature against the Foundry CLI and
service installed on this machine. It reports the CLI version and, for each feature, whether
it **passes**, **fails**, or **behaves differently** from a previous CLI version.

It needs a real Foundry Local install and real CPU/GPU/NPU models, so it **cannot run on a
GitHub runner**. Run it locally after each Foundry CLI upgrade.

## Usage

```powershell
# Run everything, compare with the closest lower CLI version in ./tests/Integration/results
./tests/Integration/Test-FoundryCompatibility.ps1

# List the features, then run a subset
./tests/Integration/Test-FoundryCompatibility.ps1 -ListFeature
./tests/Integration/Test-FoundryCompatibility.ps1 -Feature Chat*, Embedding*

# Choose the models (defaults: qwen2.5-0.5b, qwen3-embedding-0.6b, whisper-tiny if cached)
./tests/Integration/Test-FoundryCompatibility.ps1 -ChatModel 'Phi-4-mini-instruct-generic-gpu'

# Include the SDK web server (slow: builds a .NET host), compare with a given baseline
./tests/Integration/Test-FoundryCompatibility.ps1 -IncludeWebServer -BaselinePath ./tests/Integration/results/foundry-0.11.0.json
```

The script exits with code 1 when a feature fails. Use `-PassThru` to get the result objects
and `-NoSave` to skip writing files.

## Statuses

| Status | Meaning |
|---|---|
| Pass | The feature works and behaves like the baseline (or no baseline exists) |
| Diff | The feature works, but its observation differs from the baseline, or it was failing on the baseline and is fixed |
| Fail | The feature threw, wrote an error or failed an assertion. **Fail (regression)** means it passed on the baseline version |
| Skip | A prerequisite is missing (no suitable model, audio file, or an opt-in test) |

Each feature records an *observation*: stable facts such as property names, types, error ids,
embedding dimension or finish reason. Generated text is never compared; it is shown as
information in the report only. CLI warnings (stderr) are part of the observation, so a new
deprecation warning shows up as a `Diff`.

## Output

Each run writes, in `tests/Integration/results/`:

- `foundry-<version>.json` - full results; later runs use it as a baseline
- `foundry-<version>.md` - readable report

Running again on the same CLI version overwrites that version's files. Commit the JSON files
to keep a history of baselines across CLI versions (they include local paths and the OS
version, so review them first).

## Side effects

- The chat model is unloaded and loaded again (to test on-demand loading).
- `Save-FoundryModel` is called on an already cached model (no download).
- Chat logs go to a temporary folder that is removed at the end.
