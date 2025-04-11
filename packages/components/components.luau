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

local wine_versions_cache = nil

local function get_wine_versions()
    if not wine_versions_cache then
        wine_versions_cache = {}

        local groups = {
            { name = "wine_staging_tkg", title = "Wine-Staging-TkG", src = import("wine-staging-tkg-src") }
        }

        for _, group in groups do
            table.insert(wine_versions_cache, {
                name = group.name,
                title = group.title,
                versions = str.decode(str.from_bytes(fs.read_file(group.src)), "json")
            })
        end
    end

    return clone(wine_versions_cache)
end

type Settings = {
    wine: {
        selected: string,

        groups: {
            -- https://github.com/Kron4ek/Wine-Builds
            wine_staging_tkg: boolean
        }
    },

    dxvk: {
        selected: string
    }
}

local function get_settings(game_name: string | nil): Settings
    if not path.exists(settings_file_path) then
        fs.write(settings_file_path, str.encode({}, "json"))
    end

    local settings = str.decode(str.from_bytes(fs.read_file(settings_file_path)), "json")

    if not game_name then
        return settings
    end

    -- To prevent long names abuse
    game_name = str.encode(hash.calc(game_name, "seahash"), "base32")

    local function default_wine_version()
        return iter(iter(get_wine_versions()).first().versions).first().name
    end

    if not settings[game_name] then
        local iter = import("iterable")

        settings[game_name] = {
            wine = {
                selected = default_wine_version(),

                groups = {
                    wine_staging_tkg = true
                }
            },

            dxvk = {
                selected = nil
            }
        }
    else
        local valid_wine_version = iter(get_wine_versions())
            .map(function(group)
                return iter(group.versions)
                    .map(function(version) return version.name end)
            end)
            .flatten()
            .any(function(version) return version == settings[game_name].wine.selected end)

        if not valid_wine_version then
            settings[game_name].wine.selected = default_wine_version()
        end
    end

    return settings[game_name]
end

local function set_settings(game_name: string, settings: Settings)
    local full_settings = get_settings(nil)

    -- To prevent long names abuse
    game_name = str.encode(hash.calc(game_name, "seahash"), "base32")

    full_settings[game_name] = settings

    fs.write_file(settings_file_path, str.encode(full_settings, "json"))
end

return {
    -- Get special get/set_property v1 game integration API handlers
    -- for given game name. Should be unique between games. This name
    -- is used to store per-game settings.
    handle_settings = function(game_name: string)
        return {
            get_property = function(name: string)
                local settings = get_settings(game_name)

                for key in name:gmatch("([^%.]+)") do
                    if not settings[key] then
                        return nil
                    end

                    settings = settings[key]
                end

                return settings
            end,

            -- Return true if property is set, otherwise false.
            set_property = function(name: string, value: any): boolean
                local settings = get_settings(game_name)

                if name == "wine.selected" then
                    settings.wine.selected = value
                elseif name == "dxvk.selected" then
                    settings.dxvk.selected = value
                elseif name == "wine.groups.wine_staging_tkg" then
                    settings.wine.groups.wine_staging_tkg = value
                else
                    return false
                end

                set_settings(game_name, settings)

                return true
            end,

            get_layout = function()
                local settings = get_settings(game_name)

                return {
                    {
                        title = {
                            en = "Game runner",
                            ru = "Окружение игры"
                        },

                        entries = {
                            {
                                name = "wine.selected",

                                title = {
                                    en = "Wine version",
                                    ru = "Версия Wine"
                                },

                                entry = {
                                    format = "enum",

                                    values = iter(get_wine_versions())
                                        .map(function(group) return group.versions end)
                                        .flatten()
                                        .fold({}, function(values, version)
                                            values[version.name] = version.title

                                            return values
                                        end),

                                    selected = settings.wine.selected
                                }
                            },

                            {
                                name = "wine.groups",

                                title = {
                                    en = "Hide wine versions",
                                    ru = "Скрыть версии Wine"
                                },

                                entry = {
                                    format = "expandable",

                                    entries = iter(get_wine_versions())
                                        .map(function(group)
                                            return {
                                                name = `wine.groups.{group.name}`,
                                                title = group.title,

                                                entry = {
                                                    format = "switch",
                                                    value = settings.wine.groups[group.name]
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
