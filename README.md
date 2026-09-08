# cl-spec

An executable semantic IR and property framework for Common Lisp programs,
designed for both humans and LLM coding agents.

**Status: skeleton.** The module structure, the Semantic IR class hierarchy and
the registry are in place; the DSL normalization, validator, explainer,
generator and property runner are stubs that signal `not-implemented`.

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, structured explain, introspection | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/tests` | test suite | `rove` |

`cl-spec` never loads `check-it`. Load `cl-spec/check-it` to install a generator
backend into `cl-spec:*generator-backend*`.

## Usage

```lisp
(asdf:load-system :cl-spec)
(asdf:load-system :cl-spec/check-it)
```

## Testing

```bash
rove cl-spec.asd
```

## Documentation

- `docs/cl-spec-specification-v0.2-draft.md` — the specification
- `docs/superpowers/specs/` — design documents

## License

MIT
