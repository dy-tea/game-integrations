# Settings v0.0.0

A general library for managing game integration settings. Helps to construct
game settings layout and handles properties storing in a shared SQLite database.

## Integration

Add settings module to your package inputs:

```json
{
    "standard": 1,
    "inputs": {
        "settings": "http://127.0.0.1:8080/packages/settings/settings.luau"
    }
}
```

## Usage

It's recommended to follow this architecture:

```luau
local __settings = nil

-- Initialize settings object
local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "name_of_your_game",
            layout = {
                example_group = {
                    title = "Example group title",
                    description = "Example group description",

                    entries = {
                        example_entry = {
                            title = "Example entry",
                            description = "Example entry description",

                            entry = {
                                format = "switch",

                                -- Instead of `value` you specify `default` property.
                                -- It will be used as default value during database
                                -- record creation.
                                default = false
                            },

                            -- Optional database-related settings
                            options = {
                                -- Getter function is called every time whe you
                                -- retrieve a value from the database.
                                get = function(value: boolean): string
                                    if value then
                                        return "YES"
                                    else
                                        return "NO"
                                    end
                                end,

                                -- Setter function is called every time when you
                                -- write values to the database.
                                set = function(value: string): boolean
                                    return value == "YES"
                                end
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end
```

The overall design is very similar to the v1 game settings standard, except some
minor differences. Settings library returns an object with `get_property`,
`set_property` and `get_layout` functions - so exactly the object the v1 game
settings standard requires you to implement. So you only need to do this:

```luau
-- Your game integration module
return {
    -- Other fields

    -- Just set here the value returned from the settings library
    settings = import_settings()
}
```

You can also use `get_property` and `set_property` to store arbitrary values
in the settings database. This can be used by other libraries like `components`.

Licensed under [GPL-3.0](../../LICENSE).
