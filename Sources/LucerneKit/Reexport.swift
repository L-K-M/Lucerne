// LucerneKit historically contained the model/IO layer that now lives in the
// portable LucerneCore target (docs/ubuntu-port.md Phase 0). Re-export it so
// `import LucerneKit` keeps giving clients (the app target, tests, scripts)
// the whole original surface — no call-site churn from the split.
@_exported import LucerneCore
