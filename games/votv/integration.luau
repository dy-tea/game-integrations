-- VOTV integration v0.0.0
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

--!nocheck

type Variant = {
    platform: string,
    edition: string
}

type Version = {
    version: string,
    title: string,
    url: string
}

local data_dir_path: string = path.persist_dir("voices_of_the_void")

local game_dir_path: string     = path.join(data_dir_path, "game")
local game_version_path: string = path.join(game_dir_path, ".version")
local game_binary_path: string  = path.join(game_dir_path, "VotV.exe")

------------------------------------------------- Game versions -------------------------------------------------

-- Direct download links are taken from here: https://archive.org/details/votv-archive
local function list_game_versions()
    return {
        { version = "pa0082_0012", title = "Pre-Alpha 0.8.2b", url = "https://archive.org/download/votv-archive/pa0082_0012.7z" },
        { version = "pa0081_0008", title = "Pre-Alpha 0.8.1",  url = "https://archive.org/download/votv-archive/pa0081_0008.7z" },
        { version = "pa08_0017",   title = "Pre-Alpha 0.8.0",  url = "https://archive.org/download/votv-archive/pa08_0017.7z" },
        { version = "pa07_0011",   title = "Pre-Alpha 0.7.0",  url = "https://archive.org/download/votv-archive/pa07_0011.7z" }
    }
end

local function last_game_version(): Version
    local iter = import("iterable")

    return iter(list_game_versions()).first()
end

local function get_game_version_info(version: string): Version?
    local iter = import("iterable")

    return iter(list_game_versions())
        .find(function(info) return info.version == version end)
end

------------------------------------------------- Imports -------------------------------------------------

local __settings = nil
local __components = nil

local function import_settings(): { get_property: (key: string) -> any, set_property: (key: string, value: any) -> nothing }
    if not __settings then
        local iter = import("iterable")
        local i18n = import("i18n").i18n

        __settings = import("settings")({
            game = "voices_of_the_void",
            layout = {
                game = {
                    title = i18n("game"),
                    entries = {
                        version = {
                            title = i18n("game_version"),
                            entry = {
                                format = "enum",

                                values = iter(list_game_versions())
                                    .fold({}, function(values, info)
                                        values[info.version] = info.title

                                        return values
                                    end),

                                default = last_game_version().version
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

local function import_components()
    if not __components then
        local settings = import_settings()

        __components = import("components").components({
            game = "voices_of_the_void",
            settings = {
                get_property = settings.get_property,
                set_property = settings.set_property
            }
        })
    end

    return __components
end

------------------------------------------------- Game -------------------------------------------------

local function get_game_version(): string?
    if not fs.exists(game_version_path) then
        return nil
    end

    return str.from_bytes(fs.read_file(game_version_path))
end

local function set_game_version(version: string)
    fs.write_file(game_version_path, str.to_bytes(version))
end

local function is_game_installed(): boolean
    local version = get_game_version()

    if not version then
        return false
    end

    local settings = import_settings()

    return version == settings.get_property("game.version")
end

------------------------------------------------- Module -------------------------------------------------

return {
    standard = 1,

    game = {
        get_status = function(variant: Variant)
            local components = import_components()

            local status = components.game.get_status(variant)

            if status then
                return status
            end

            if not is_game_installed() then
                return "not-installed"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            local settings = import_settings()
            local components = import_components()

            local diff = components.game.get_diff(variant)

            if diff then
                return diff
            end

            if is_game_installed() then
                return nil
            end

            local selected_game_version = settings.get_property("game.version")

            local info = get_game_version_info(selected_game_version)

            if not info then
                error(`invalid game version selected: {selected_game_version}`)
            end

            local i18n = import("i18n").i18n

            local archive_path: string = path.join(path.temp_dir(), `votv_{info.version}.7z`)

            return {
                title = i18n("install_game"),

                pipeline = {
                    {
                        title = i18n("delete_old_files"),

                        before = function()
                            return fs.exists(game_dir_path)
                        end,

                        perform = function()
                            fs.remove_dir(game_dir_path)
                        end
                    },

                    {
                        title = i18n("download_game_files"),

                        perform = function(updater)
                            local downloader_handle = downloader.create()

                            local task_handle = downloader.download(downloader_handle, {
                                url = info.url,
                                output_file = archive_path,
                                continue_download = true,

                                on_update = function(current: number, total: number)
                                    updater({
                                        progress = {
                                            current = current,
                                            total = total,

                                            format = function()
                                                local current = current / 1000 / 1000 / 1000
                                                local total = total / 1000 / 1000 / 1000

                                                return i18n("downloading_progress", {
                                                    current = math.floor(current * 100) / 100,
                                                    total = math.floor(total * 100) / 100
                                                })
                                            end
                                        }
                                    })
                                end
                            })

                            downloader.wait(task_handle)
                            downloader.close(downloader_handle)
                        end
                    },

                    {
                        title = i18n("extract_game_files"),

                        perform = function(updater)
                            local handle: number = archive.open(archive_path)

                            archive.extract(handle, data_dir_path, function(current: number, total: number)
                                updater({
                                    progress = {
                                        current = current,
                                        total = total,

                                        format = function()
                                            local current = current / 1000 / 1000 / 1000
                                            local total = total / 1000 / 1000 / 1000

                                            return i18n("extraction_progress", {
                                                current = math.floor(current * 100) / 100,
                                                total = math.floor(total * 100) / 100
                                            })
                                        end
                                    }
                                })
                            end)

                            archive.close(handle)

                            fs.move(path.join(data_dir_path, info.version, "WindowsNoEditor"), game_dir_path)
                            fs.remove(path.join(data_dir_path, info.version))
                            fs.remove(archive_path)

                            set_game_version(info.version)
                        end
                    }
                }
            }
        end,

        get_launch_info = function(variant: Variant)
            if not is_game_installed() then
                return {
                    status = "disabled",
                    binary = game_binary_path
                }
            end

            local components = import_components()

            return components.game.wrap_launch_info({
                status = "normal",
                binary = game_binary_path
            })
        end
    },

    settings = {
        get_property = function(name: string): any
            local settings = import_settings()

            return settings.get_property(name)
        end,

        set_property = function(name: string, value: any)
            local settings = import_settings()

            settings.set_property(name, value)
        end,

        get_layout = function(variant: Variant)
            local iter = import("iterable")

            local settings = import_settings()
            local components = import_components()

            return iter(settings.get_layout(variant))
                .chain(components.settings.get_layout())
                .collect()
        end
    }
}
