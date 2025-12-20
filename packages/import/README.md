# import v0.1.0

A simple function to import other modules or packages using standard `load`
function.

## Integration

Add `import` luau module to your integration package inputs:

```json
{
    "version": 1,
    "inputs": {
        "import": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/import/import.luau"
    }
}
```

## Usage

Provided `import` function will resolve lua modules and packages, and load
files and folders as paths.

```luau
local import = load("import").value

local example_module, example_package = import("example_module", "example_package")
```

Or pre-define `import` function like this:

```luau
function import(...)
    return (load("import").value)(...)
end

local example_module, example_package = import("example_module", "example_package")
```

Licensed under [GPL-3.0-or-later](../../LICENSE).
