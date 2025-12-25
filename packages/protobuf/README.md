# Protobuf v0.1.0

Wrapper of a `protoc` binary which allows you to encode and decode protobuf
messages.

## Integration

Add protobuf module to your package inputs:

```json
{
    "format": 1,
    "inputs": {
        "protobuf": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/protobuf/protobuf.luau"
    }
}
```

## Usage

```luau
local protobuf = load("protobuf").value
local platform = "x86_64-linux"

if not protobuf.is_supported(platform) then
    error(`{platform} is not supported`)
end

if not protobuf.is_installed(platform) then
    protobuf.install(platform, function(current, total)
        print(`{current} / {total}`)
    end)
end

-- Make sure to provide path which can be read by the protobuf module
local protobuf_path = path.join(path.temp_dir(), "example.proto")

fs.write_file(protobuf_path, "syntax = \"proto3\"; message Test { string value = 1; }")

local encoded_message = protobuf.encode(platform, {
    protobuf = protobuf_path,
    type = "Test",
    input = "value: \"Hello, World!\"" -- or path to input file
})

local decoded_message = protobuf.decode(platform, {
    protobuf = protobuf_path,
    type = "Test",
    input = encoded_message -- or path to input file
})

assert(decoded_message == "value: \"Hello, World!\"\n")
```

Licensed under [GPL-3.0-or-later](../../LICENSE).
