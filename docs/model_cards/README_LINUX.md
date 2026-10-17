# Generate Model Cards

**Linux/bash port of [Generate Model Cards](README.md).** The original uses a Windows PowerShell command; this port uses the bash equivalent.

This directory intentionally contains no pre-evaluated model cards or model
bundles. After data preparation and model registration, run from the project root:

```bash
.venv/bin/python -m scripts.responsible.run_analysis
```

This generates `demand.md` and `fare.md` here, plus fairness JSON and SHAP plots
under `artifacts/responsible/`. For fare alone, add `--problem fare`.
Follow [setup](../SETUP_LINUX.md) first. Preserve outputs before regenerating them.

Record your data period, generation time, evaluated model reference, and any
unresolved numeric-version identity. These reports describe your run; they are
not proof that a deployed service uses the same model. A mutable `latest`
reference is not immutable provenance.

Dashboard cloud builds require the actual generated cards, not just this README.
Publish and restore your own cards into the build context before releasing an
image intended to display them. Do not copy another account's model artifacts.
