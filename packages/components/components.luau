-- components v0.0.0
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

local data_dir_path = path.persist_dir("components")
local settings_file_path = path.join(data_dir_path, "settings.json")

------------------------------------------------- Imports -------------------------------------------------

-- Since inputs of a package can't access other inputs
-- of the same package here we implicitly feed them
-- with all the necessary info.

local function import_wine()
    local wine = import("wine")

    return wine({
        wine_staging_tkg = fs.read_file(import("wine-staging-tkg-src"))
    })
end

local function import_dxvk()
    local wine = import("dxvk")

    return wine({
        dxvk = fs.read_file(import("dxvk-src")),
        dxvk_gplasync = fs.read_file(import("dxvk-gplasync-src"))
    })
end

------------------------------------------------- Settings -------------------------------------------------

type Settings = {
    wine: {
        selected: string,

        groups: {
            -- https://github.com/Kron4ek/Wine-Builds
            wine_staging_tkg: boolean
        }
    },

    dxvk: {
        selected: string,

        groups: {
            -- https://github.com/doitsujin/dxvk
            dxvk: boolean,

            -- https://gitlab.com/Ph42oN/dxvk-gplasync
            dxvk_gplasync: boolean
        }
    }
}

local function get_settings_keys(): table
    local keys = {
        "wine.selected",
        "wine.groups.wine_staging_tkg",

        "dxvk.selected",
        "dxvk.groups.dxvk",
        "dxvk.groups.dxvk_gplasync"
    }

    local values = {}

    for _, key in ipairs(keys) do
        local path = {}

        for component in key:gmatch("([^%.]+)") do
            table.insert(path, component)
        end

        values[key] = path
    end

    return values
end

local function get_settings(game_name: string | nil): Settings
    if not path.exists(settings_file_path) then
        fs.write_file(settings_file_path, str.to_bytes("{}"))
    end

    local settings = str.decode(str.from_bytes(fs.read_file(settings_file_path)), "json")

    if not game_name then
        return settings
    end

    local iter = import("iterable")

    local wine = import_wine()
    local dxvk = import_dxvk()

    local function default_wine_version()
        return iter(iter(wine.get_versions()).first().versions).first().name
    end

    local function default_dxvk_version()
        return iter(iter(dxvk.get_versions()).first().versions).first().name
    end

    if not settings[game_name] then
        settings[game_name] = {
            wine = {
                selected = default_wine_version(),

                groups = {
                    wine_staging_tkg = true
                }
            },

            dxvk = {
                selected = default_dxvk_version(),

                groups = {
                    dxvk = true,
                    dxvk_gplasync = true
                }
            }
        }
    else
        local valid_wine_version = iter(wine.get_versions())
            .map(function(group)
                return iter(group.versions)
                    .map(function(version) return version.name end)
            end)
            .flatten()
            .any(function(version) return version == settings[game_name].wine.selected end)

        if not valid_wine_version then
            settings[game_name].wine.selected = default_wine_version()
        end

        local valid_dxvk_version = iter(dxvk.get_versions())
            .map(function(group)
                return iter(group.versions)
                    .map(function(version) return version.name end)
            end)
            .flatten()
            .any(function(version) return version == settings[game_name].wine.selected end)

        if not valid_dxvk_version then
            settings[game_name].dxvk.selected = default_dxvk_version()
        end
    end

    return settings[game_name]
end

local function set_settings(game_name: string, settings: Settings)
    local full_settings = get_settings(nil)

    full_settings[game_name] = settings

    fs.write_file(settings_file_path, str.to_bytes(str.encode(full_settings, "json")))
end

------------------------------------------------- Module -------------------------------------------------

return {
    -- Get special get/set_property v1 game integration API handlers
    -- for given game name. Should be unique between games. This name
    -- is used to store per-game settings.
    handle_settings = function(game_name: string)
        return {
            get_property = function(name: string)
                local settings_layout = get_settings_keys()

                if not settings_layout[name] then
                    return nil
                end

                local settings = get_settings(game_name)

                for _, component in pairs(settings_layout[name]) do
                    settings = settings[component]
                end

                return settings
            end,

            -- Return true if property is set, otherwise false.
            set_property = function(name: string, value: any): boolean
                local settings_layout = get_settings_keys()

                if not settings_layout[name] then
                    return false
                end

                local settings = get_settings(game_name)
                local traversable = settings

                for i, key in ipairs(settings_layout[name]) do
                    -- If you change a key of a table - its value will be updated
                    -- even if this table is nested due to lua tables quirks.
                    -- We're abusing this feature here.
                    if i == #settings_layout[name] then
                        traversable[key] = value
                    else
                        traversable = traversable[key]
                    end
                end

                set_settings(game_name, settings)

                return true
            end,

            get_layout = function()
                local iter = import("iterable")
                local i18n = import("i18n").i18n

                local wine = import_wine()
                local dxvk = import_dxvk()

                local settings = get_settings(game_name)

                return {
                    {
                        title = i18n("game_runner") or "Game runner",

                        entries = {
                            {
                                name = "wine.selected",
                                title = i18n("wine_version") or "Wine version",

                                entry = {
                                    format = "enum",

                                    values = iter(wine.get_versions())
<<<<<<< HEAD
                                        .map(function(group)
                                            return iter(group.versions)
                                                .map(function(version)
                                                    return {
                                                        group = group.name,
                                                        version = version
                                                    }
                                                end)
                                                .collect()
                                        end)
=======
                                        .map(function(group) return group.versions end)
>>>>>>> 17190a1 (feat(packages/components): add DXVK editions)
                                        .flatten()
                                        .filter(function(version)
                                            return settings.wine.groups[version.group] or version.version.name == settings.wine.selected
                                        end)
                                        .fold({}, function(values, version)
                                            values[version.version.name] = version.version.title

                                            return values
                                        end),

                                    selected = settings.wine.selected
                                }
                            },

                            {
                                name = "dxvk.selected",
                                title = i18n("dxvk_version") or "DXVK version",

                                entry = {
                                    format = "enum",

                                    values = iter(dxvk.get_versions())
<<<<<<< HEAD
                                        .map(function(group)
                                            return iter(group.versions)
                                                .map(function(version)
                                                    return {
                                                        group = group.name,
                                                        version = version
                                                    }
                                                end)
                                                .collect()
                                        end)
                                        .flatten()
                                        .filter(function(version)
                                            return settings.dxvk.groups[version.group] or version.version.name == settings.dxvk.selected
                                        end)
                                        .fold({}, function(values, version)
                                            values[version.version.name] = version.version.title
=======
                                        .map(function(group) return group.versions end)
                                        .flatten()
                                        .fold({}, function(values, version)
                                            values[version.name] = version.title
>>>>>>> 17190a1 (feat(packages/components): add DXVK editions)

                                            return values
                                        end),

                                    selected = settings.dxvk.selected
                                }
                            },

                            {
                                title = i18n("available_wine_editions") or "Available wine editions",

                                entry = {
                                    format = "expandable",

                                    entries = iter(wine.get_versions())
                                        .map(function(group)
                                            return {
                                                name = `wine.groups.{group.name}`,
                                                title = group.title,

                                                reactivity = "release",

                                                entry = {
                                                    format = "switch",
                                                    value = settings.wine.groups[group.name]
                                                }
                                            }
                                        end)
                                        .collect()
                                }
                            },

                            {
                                title = i18n("available_dxvk_editions") or "Available DXVK editions",

                                entry = {
                                    format = "expandable",

                                    entries = iter(dxvk.get_versions())
                                        .map(function(group)
                                            return {
                                                name = `dxvk.groups.{group.name}`,
                                                title = group.title,

                                                reactivity = "release",

                                                entry = {
                                                    format = "switch",
                                                    value = settings.dxvk.groups[group.name]
                                                }
                                            }
                                        end)
                                        .collect()
                                }
                            }
                        }
                    }
                }
            end
        }
    end
}
