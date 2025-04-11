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

type Variant = {
    platform: string,
    edition: string
}

type Version = {
    version: string,
    title: string,
    url: string
}

-- Direct download links are taken from here: https://archive.org/details/votv-archive
local game_versions = {
    { version = "pa0082_0012", title = "Pre-Alpha 0.8.2b", url = "https://archive.org/download/votv-archive/pa0082_0012.7z" },
    { version = "pa0081_0008", title = "Pre-Alpha 0.8.1",  url = "https://archive.org/download/votv-archive/pa0081_0008.7z" },
    { version = "pa08_0017",   title = "Pre-Alpha 0.8.0",  url = "https://archive.org/download/votv-archive/pa08_0017.7z" },
    { version = "pa07_0011",   title = "Pre-Alpha 0.7.0",  url = "https://archive.org/download/votv-archive/pa07_0011.7z" }
}

local data_path = path.persist_dir("voices_of_the_void")

local game_path = path.join(data_path, "game")
local game_version_path = path.join(game_path, ".version")

local function last_game_version(): Version
    local iter = import("iterable")

    return iter(clone(game_versions)).next().value
end

local function get_game_version(): Version | nil
    if not fs.exists(game_version_path) then
        return nil
    end

    local iter = import("iterable")

    local version = str.from_bytes(fs.read_file(game_version_path))

    for _, info in iter(clone(game_versions)) do
        if version == info.version then
            return info
        end
    end

    return nil
end

local function set_game_version(version: string)
    fs.write_file(game_version_path, str.to_bytes(version))
end

local function delete_game()
    pcall(fs.remove_dir, game_path)
end

local function get_components_settings()
    return import("components").components.handle_settings("voices_of_the_void")
end

return {
    standard = 1,

    editions = function(platform: string)
        return {
            {
                name = "default",
                title = {
                    en = "Default",
                    ru = "Стандартная"
                }
            }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            if not get_game_version() then
                return "not-installed"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            if get_game_version() then
                return nil
            end

            local info = last_game_version()

            local archive_path = path.join(path.temp_dir(), `votv_{info.version}.7z`)

            return {
                title = {
                    en = "Install game",
                    ru = "Установить игру"
                },

                pipeline = {
                    {
                        title = {
                            en = "Delete",
                            ru = "Удалить"
                        },

                        description = {
                            en = "Download previous game version",
                            ru = "Удаление предыдущей версии игры"
                        },

                        perform = function(progress)
                            delete_game()
                        end
                    },

                    {
                        title = {
                            en = "Download",
                            ru = "Скачать"
                        },

                        description = {
                            en = "Download archives with game files",
                            ru = "Скачать архивы с файлами игры"
                        },

                        perform = function(updater)
                            downloader.download(info.url, {
                                output_file = archive_path,
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

                                                return {
                                                    en = `Downloaded {current} GB / {total} GB`,
                                                    ru = `Скачано {current} ГБ / {total} ГБ`
                                                }
                                            end
                                        }
                                    })
                                end
                            })
                        end
                    },

                    {
                        title = {
                            en = "Extract",
                            ru = "Распаковать"
                        },

                        description = {
                            en = "Extract game files from archives",
                            ru = "Распаковать файлы игры из архивов"
                        },

                        perform = function(updater)
                            local handle = archive.open(archive_path)

                            archive.extract(handle, data_path, function(current, total, diff)
                                updater({
                                    progress = {
                                        current = current,
                                        total = total,

                                        format = function()
                                            local current = current / 1000 / 1000 / 1000
                                            local total = total / 1000 / 1000 / 1000

                                            current = math.floor(current * 100) / 100
                                            total = math.floor(total * 100) / 100

                                            return {
                                                en = `Extracted {current} GB / {total} GB`,
                                                ru = `Распаковано {current} ГБ / {total} ГБ`
                                            }
                                        end
                                    }
                                })
                            end)

                            archive.close(handle)

                            fs.move(path.join(data_path, info.version, "WindowsNoEditor"), game_path)
                            fs.remove(path.join(data_path, info.version))
                            fs.remove(archive_path)

                            set_game_version(info.version)
                        end
                    }
                }
            }
        end,

        get_launch_info = function(variant: Variant)
            return {
                status = "disabled",
                hint = {
                    en = "It's a test implementation not meant for real use",
                    ru = "Это тестовая реализация, не предназначенная для реального использования"
                },
                binary = ""
            }
        end
    },

    settings = {
        get_property = function(name: string)
            return get_components_settings().get_property(name)
        end,

        set_property = function(name: string, value: any)
            get_components_settings().set_property(name, value)
        end,

        get_layout = function(variant: Variant)
            local iter = import("iterable")

            local versions_enum = {}

            for _, info in iter(clone(game_versions)) do
                versions_enum[info.version] = info.title
            end

            local layout = {
                {
                    title = {
                        en = "Game",
                        ru = "Игра"
                    },

                    entries = {
                        {
                            name = "game.version",

                            title = {
                                en = "Game version",
                                ru = "Версия игры"
                            },

                            entry = {
                                format = "enum",
                                values = versions_enum,
                                selected = last_game_version().version
                            }
                        }
                    }
                }
            }

            return iter(layout)
                .chain(get_components_settings().get_layout())
                .collect()
        end
    }
}
