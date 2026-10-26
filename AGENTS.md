# momi-dlss5: instructions for AI agents

Read [HANDOVER.md](HANDOVER.md) before doing anything. It has the current status, the next tasks in order, the repo rules and technical notes. Background facts are in [docs/research-summary.md](docs/research-summary.md).

The short version of the rules:
- The repo is public. No client data, internal host names, IPs or credentials.
- No NVIDIA binaries in the repo.
- Never download or run the leaked DLSS 5 runtime yourself.
- Keep `test-kit/Convert-ExrToTiff.ps1` compatible with Windows PowerShell 5.1 (ASCII only). Run `python test-kit/tests/test_converter.py` after changing it.
- `test-kit/ab-review.html` stays one offline file with no network calls.
