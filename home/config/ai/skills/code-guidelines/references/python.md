# Python

## Tooling

- Projects use uv with uv2nix: the dev shell provides the virtualenv,
  `basedpyright` and `ruff`. `UV_NO_SYNC` is set, so uv never installs into the
  environment.
- Add a dependency: edit `pyproject.toml`, run `uv lock`, then `direnv reload`
  so Nix rebuilds the virtualenv. Never `pip install` or `uv pip install`.
- Format and lint: `ruff format`, `ruff check`. Types: `basedpyright`, clean
  before reporting done.
- Target the `requires-python` version; use its features (`match`,
  `type` aliases, PEP 695 generics).

## Types

- Annotate every function signature and module-level value. No `Any`; use
  `object` plus narrowing at boundaries.
- `dataclass(frozen=True, slots=True)` or `NamedTuple` for records; no bare
  dicts or tuples passed between functions.
- `Enum` or `Literal` unions over string flags and booleans.
- `X | None` for optional values; handle `None` explicitly.
- Validate external data (JSON, env, CLI args, files) once at the boundary into
  typed objects.
- No `cast` or `# type: ignore` without a reason in the commit message.

## Errors

- Raise specific exceptions, custom subclasses for domain errors. Never bare
  `except:` or `except Exception: pass`.
- `raise ... from error` to keep the cause.
- CLIs catch at the top level and exit with a message and non-zero status.

## Structure

- `src/` layout, entry point in `[project.scripts]`.
- Functions over classes unless there is state to encapsulate.
- `pathlib.Path` over `os.path`; `subprocess.run([...], check=True)` with list
  arguments, never `shell=True` with interpolated strings.
- No mutable default arguments. No module-level side effects beyond constants.
- Standard library first; add a dependency only when it replaces substantial
  code.

## Testing

- pytest. Plain `assert`; `pytest.mark.parametrize` for input tables;
  `tmp_path` and `monkeypatch` over hand-rolled fixtures.
- Test names `test_<action>_<condition>_<expected>`.
