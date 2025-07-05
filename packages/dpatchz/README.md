# dpatchz v0.0.0

Module for patching files with dpatchz (modified hdiffpatch also known as krdiff).

## Integration

Add dpatchz module to your package inputs:

```json
{
    "standard": 1,
    "inputs": {
        "dpatchz": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/dpatchz/dpatchz.luau"
    }
}
```

Import the module:

```luau
-- Import the dpatchz library
local dpatchz = import("dpatchz")
```

## Examples

```luau
local dpatchz = import("dpatchz")

dpatchz.patch_file(diff_path, old_path, new_path) -- will execute `dpatchz $diff_path $old_path $new_path`

dpatchz.patch_file(diff_path, base_path) -- will execute `dpatchz -i $diff_path $base_path`
```
