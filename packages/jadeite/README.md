# jadeite v0.0.0

## Integration

Add jadeite module to your package inputs:

```json
{
    "standard": 1,
    "inputs": {
        "jadeite": "http://127.0.0.1:8080/packages/jadeite/jadeite.luau"
    }
}
```

Import the module:

```luau
-- Import the jadeite library
local jadeite = import("jadeite")
```

## Examples

```luau
local jadeite = import("jadeite")

-- in your get_launch_info function

return jadeite.wrap_launch_command({
  status = "normal",
  binary = "path/to/binary"
})
```

You will want to use the `jadeite.wrap_launch_command` in conjunction with the components package (wine) to launch your game.

```luau
local jadeite = import("jadeite")

-- in your get_launch_info function

local components = import_components() -- user-defined function

return components.game.wrap_launch_info(jadeite.wrap_launch_command({
  status = "normal",
  binary = "path/to/binary"
}))
```

You can specify a version by passing it as the second argument to `jadeite.wrap_launch_command`, the latest version will be used if no version is specified.

```luau
local jadeite = import("jadeite")

-- in your get_launch_info function

return jadeite.wrap_launch_command({
  status = "normal",
  binary = "path/to/binary"
}, "v2.0.0")
```
