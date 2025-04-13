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

local wine_dir_path        = path.join(data_dir_path, "wine")
local wine_prefix_dir_path = path.join(data_dir_path, "prefix")
local dxvk_dir_path        = path.join(data_dir_path, "dxvk")

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
        prefix: string,
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

local function filter_wine_prefix_name(name: string | nil): string
    if name then
        name = name:gsub("^%s+", "")
    	name = name:gsub("%s+$", "")
    	name = name:gsub("[^%a%d]", "_")
    end

	if not name or string.len(name) == 0 then
	   name = "games"
	end

	return name
end

local function get_settings_keys(): table
    local function identity(value) return value end

    local keys = {
        ["wine.prefix"] = filter_wine_prefix_name,
        ["wine.selected"] = identity,
        ["wine.groups.wine_staging_tkg"] = identity,

        ["dxvk.selected"] = identity,
        ["dxvk.groups.dxvk"] = identity,
        ["dxvk.groups.dxvk_gplasync"] = identity
    }

    local values = {}

    for key, setter in pairs(keys) do
        local path = {}

        for component in key:gmatch("([^%.]+)") do
            table.insert(path, component)
        end

        values[key] = {
            path = path,
            setter = setter
        }
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
                prefix = "games",
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
        settings[game_name].wine.prefix = filter_wine_prefix_name(settings[game_name].wine.prefix)

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
    -- Get special v1 game integration API handlers for given game name.
    -- Should be unique between games. This name is used to store per-game settings.
    handle_settings = function(game_name: string)
        -- Return pipeline of actions needed to prepare game runner.
        local function get_runner_diff_pipeline()
            local iter = import("iterable")
            local i18n = import("i18n").i18n

            local wine = import_wine()
            local dxvk = import_dxvk()

            local settings = get_settings(game_name)

            local selected_wine = iter(wine.get_versions())
                .map(function(group) return group.versions end)
                .flatten()
                .find(function(version) return version.name == settings.wine.selected end)
                .value

            if not selected_wine then
                error("Failed to find selected wine version")
            end

            local wine_data_path = path.join(wine_dir_path, settings.wine.selected)
            local wine_prefix_path = path.join(wine_prefix_dir_path, settings.wine.prefix)

            local should_update_wine = not fs.exists(path.join(wine_data_path, selected_wine.features.binary))
            local should_update_prefix = not wine.prefix.is_valid(wine_prefix_path) or wine.prefix.get_wine_name(wine_prefix_path) ~= settings.wine.selected

            if not should_update_wine and not should_update_prefix then
                return nil
            end

            local wine_download_output = path.join(path.temp_dir(), selected_wine.file)

            return {
                title = i18n("update_game_runner") or "Update game runner",

                pipeline = {
                    {
                        title = i18n("update_wine_version") or "Update wine version",

                        before = function() return should_update_wine end,

                        perform = function(updater)
                            downloader.download(selected_wine.url, {
                                output_file = wine_download_output,
                                continue_downloading = true,

                                progress = function(current, total, diff)
                                    updater({
                                        progress = {
                                            current = current,
                                            total = total,

                                            format = function()
                                                local current = current / 1000 / 1000 / 1000
                                                local total = total / 1000 / 1000 / 1000

                                                current = math.floor(current * 100) / 100
                                                total = math.floor(total * 100) / 100

                                                return i18n("downloading_progress", {
                                                    current = current,
                                                    total = total
                                                }) or `Downloading: {current / total * 100}%`
                                            end
                                        }
                                    })
                                end
                            })
                        end
                    },

                    {
                        title = i18n("update_wine_version") or "Update wine version",

                        before = function() return should_update_wine end,

                        perform = function(updater)
                            local handle = archive.open(wine_download_output)

                            -- wine_dir_path instead of wine_data_path because we expect
                            -- every wine build archive to contain a parent folder inside.
                            archive.extract(handle, wine_dir_path, function(current, total, diff)
                                updater({
                                    progress = {
                                        current = current,
                                        total = total,

                                        format = function()
                                            local current = current / 1000 / 1000 / 1000
                                            local total = total / 1000 / 1000 / 1000

                                            current = math.floor(current * 100) / 100
                                            total = math.floor(total * 100) / 100

                                            return i18n("extraction_progress", {
                                                current = current,
                                                total = total
                                            }) or `Extracting: {current / total * 100}%`
                                        end
                                    }
                                })
                            end)

                            archive.close(handle)

                            fs.remove(wine_download_output)
                        end
                    },

                    {
                        title = i18n("update_wine_prefix") or "Update wine prefix",

                        before = function() return should_update_prefix end,

                        perform = function(updater)
                            fs.create_dir(wine_prefix_path)

                            wine.prefix.update(settings.wine.selected, wine_prefix_path)
                        end
                    }
                }
            }
        end

        return {
            get_game_status = function()
                if not get_runner_diff_pipeline() then
                    return nil
                end

                return "update-required"
            end,

            get_game_diff = function()
                return get_runner_diff_pipeline()
            end,

            get_property = function(name: string)
                local settings_layout = get_settings_keys()

                if not settings_layout[name] then
                    return nil
                end

                local settings = get_settings(game_name)

                for _, component in pairs(settings_layout[name].path) do
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

                for i, key in ipairs(settings_layout[name].path) do
                    -- If you change a key of a table - its value will be updated
                    -- even if this table is nested due to lua tables quirks.
                    -- We're abusing this feature here.
                    if i == #settings_layout[name].path then
                        traversable[key] = settings_layout[name].setter(value)
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
                                name = "wine.prefix",

                                title = i18n("wine_prefix_name") or "Wine prefix name",
                                description = i18n("wine_prefix_name_description"),

                                entry = {
                                    format = "text",
                                    value = settings.wine.prefix
                                }
                            },

                            {
                                name = "wine.selected",
                                title = i18n("wine_version") or "Wine version",

                                entry = {
                                    format = "enum",

                                    values = iter(wine.get_versions())
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
