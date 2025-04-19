# Hyvlib

Hyvlib is a general purpose library for HYV games. It supports common
HYV-specific API format, games installation, updating and patching methods.

## Integration

Add hyvlib package to your integration package inputs:

```json
{
    "standard": 1,
    "inputs": {
        "hyvlib": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/hyvlib/package.json"
    }
}
```

Hyvlib exposes a single output, a function taking the game name. The intended usage is calling it once at the top of your integration script:
```lua
local hyvlib = import("hyvlib").hyvlib("game")
```

The above will give you another function, which takes the game edition and returns an info object:
```lua
local info_object = hyvlib("edition")
```

API responses are cached, so most hyvlib calls are very cheap.

## Info object

The info object represents information about the game on the API, and can be used to obtain a game object.

### `info_object.get_main_version(): Semver`
Returns the latest non-predownload version of the game available on the API.

### `info_object.get_predownload_version(): Semver?`
Returns the version of the predownload, if one is avaiable. Otherwise returns nil.

### `info_object.open_game_folder(game_folder: string): GameObject`
Returns a game object representing the game folder at the specified path. The folder does not have to exist, as the game not being installed is a valid state.

```lua
local game_object = info_object.open_game_folder("My Game Folder") 
```

## Game object
The game object represents a potential game installation at a specified path. All functions on it require a self reference, and should be called using the `object:method()` syntax. Note that some methods require a version file to be present.

The `InstalledVersion` type is the parsed form of a `version.toml` file managed by hyvlib. This file separately tracks the versions of the game and audio packages. Keys of the optional `audio` table are language codes, e.g. `en-us` or `zh-cn`.

```luau
type InstalledVersion = {
    game: Semver,
    audio: { 
        [string]: Semver 
    }?
}
```

### `game_object:get_installed_version(): InstalledVersion?`
Reads and parses the version file of this installation. If it does not exist, returns nil. If there exists a valid game installation, such a file must be present for some hyvlib features to function. Use `set_installed_version` to create it manually.

### `game_object:set_installed_version(version: InstalledVersion)`
Overwrites the version file with the provided data. This must be done when importing an existing game installation:

```lua
if not game_object:get_installed_version() then
    -- Some kind of game-specific algorithm should be implemented
    -- to guess the package list and version from the game files
    local guessed_version = {
        game = "1.2.3",
        audio = {
            ["en-us"] = "1.2.3"
        }
    }

    game_object:set_installed_version(guessed_version) 
end
```

### `game_object:get_exe_path(): string`
This method **does not** require a valid version file.

Returns the full path to the game executable (this is an API field). 

### `game_object:get_audio_package_path(): string`
This method **does not** require a valid version file.

Returns the full path to the folder where installed audio packages are located (this is an API field). Note that the names of the package folders are game-specific, and are not the same as the language codes. 

### `game_object:is_installed(): boolean`
This method **does not** require a valid version file.

Returns whether the game files exist and whether the installation process has completed. The former is implemented by checking whether the game executable exists.

If an `is_installing` file exists in the game folder, the method will always return false. This file is created during installation to avoid a situation where the game will be falsely considered installed if unpacking was interrupted after the game executable has already been unpacked.

### `game_object:is_update_required([enabled_audio: { string }?]): boolean`
This method **requires** a valid version file.

Checks whether a newer version than currently installed is main on the API. 

`enabled_audio` is a list of language codes of required audio packages. If an audio package that is not installed is specified, this method will return true (update from the "not installed" state to latest is required). **If not all installed audio packages are specified in this argument, the missing ones will be ignored.**

### `game_object:make_update_diff(temp_folder: string, [enabled_audio: { string }?]): InstallationDiff`
If the game is already installed, this method **requires** a valid version file. Absense of a version file is treated as requesting an update from the "not installed" state to latest.

Creates a diff that can be returned from the `get_diff` method of an integration. Its pipeline will update or install the game and the enabled audio packages. If a delta package exists, it will be used, otherwise the pipeline will perform a full download. **(deltas are not implemented at time of writing)**

`enabled_audio` is a list of language codes of required audio packages. If an audio package that is not installed is specified, the returned pipeline will install it. **If not all installed audio packages are specified in this argument, the missing ones will be ignored. The pipeline will not remove them.**

The returned pipeline can be interrupted at any time, and hyvlib will try it's best to resume gracefully after restarting. If `is_installed` returns false, an additional file named `is_installing` will be created, so that the process can be continued after interruption. The file will be deleted after installation finishes.

### `game_object:find_deprecated_files(): { string }`
This method **does not** require a valid version file.

Finds files that **must** be deleted in the game folder, and returns a list of full paths to them. The presence of these files can cause integrity error messages, preventing login in the game.

The API endpoint this method abstracts away only has data for one game at the time of writing. For all other games, an empty table will always be returned.

Licensed under [GPL-3.0](../../LICENSE).
