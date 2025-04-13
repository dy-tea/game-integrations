-- components/wine v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

type Features = {
    binary: string,
    env: table | nil
}

type Output = {
    -- Exit code of the process.
    status: number | null,

    -- Was the process closed normally.
    is_ok: boolean,

    -- Output of the process.
    stdout: {number},
    stderr: {number}
}

type LaunchCommand = {
    binary: string,
    args: {string} | nil,
    env: table | nil
}

local data_dir_path = path.persist_dir("components")
local wine_dir_path = path.join(data_dir_path, "wine")

return function(imports)
    local wine_versions_cache = nil

    local function get_versions()
        if not wine_versions_cache then
            wine_versions_cache = {}

            local groups = {
                { name = "wine_staging_tkg", title = "Wine-Staging-TkG", src = imports.wine_staging_tkg }
            }

            for _, group in groups do
                table.insert(wine_versions_cache, {
                    name = group.name,
                    title = group.title,
                    versions = str.decode(str.from_bytes(group.src), "json")
                })
            end
        end

        return clone(wine_versions_cache)
    end

    -- Try to find features of the wine version with provided name.
    local function get_version_features(name: string): Features | nil
        local iter = import("iterable")

        local version = iter(get_versions())
            .map(function(group) return group.versions end)
            .flatten()
            .find(function(version) return version.name == name end)

        if not version then
            return nil
        end

        return version.value.features
    end

    -- Run wine with provided name, arguments and environment variables.
    -- Return true if command run successfully, otherwise false.
    local function run(name: string, args: {string}, env: table | nil): Output | nil
        local features = get_version_features(name)

        if not features then
            error(`Invalid wine version name: '{name}'`)
        end

        local wine_path = path.join(wine_dir_path, name, features.binary)

        if not fs.exists(wine_path) then
            error(`Wine version '{name}' is not installed or invalid`)
        end

        if not env then
            env = {}
        end

        if features.env then
            for k, v in pairs(features.env) do
                env[k] = v
            end
        end

        return process.exec(wine_path, args, env)
    end

    -- Create or update wine prefix with provided version name and prefix path.
    local function update_prefix(name: string, prefix: string)
        run(name, { "wineboot" }, { WINEPREFIX = prefix })
    end

    -- Wrap provided launch command with selected wine version name.
    -- Basically adds `wine` to the beginning of the command and merges
    -- environment variables.
    local function wrap_launch_command(name: string, command: LaunchCommand): LaunchCommand
        local features = get_version_features(name)

        if not features then
            error(`Invalid wine version name: '{name}'`)
        end

        local wrap = {
            binary = features.binary,
            args = { command.binary },
            env = features.env or {}
        }

        if command.args then
            for _, arg in pairs(command.args) do
                table.insert(wrap.args, arg)
            end
        end

        if command.env then
            for k, v in pairs(command.env) do
                wrap.env[k] = v
            end
        end

        return wrap
    end

    return {
        get_versions = get_versions,
        update_prefix = update_prefix,
        wrap_launch_command = wrap_launch_command
    }
end
