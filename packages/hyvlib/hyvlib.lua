-- hyvlib v0.0.0
-- Copyright (C) 2024  Nikita Podvirnyi <krypt0nn@vk.com>
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

local editions_locales = {
    global = {
        en = "Global",
        ru = "Глобальная",
        zh = "全球"
    },

    china = {
        en = "Chinese",
        ru = "Китайская",
        zh = "中文"
    }
}

local games = {
    genshin = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "hk4e_global",
                title = editions_locales.global,
                entries = {
                    data_folder = "GenshinImpact_Data",
                    version_file = "globalgamemanagers"
                } 
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "hk4e_cn",
                title = editions_locales.china,
                entries = {
                    data_folder = "YuanShen_Data",
                    version_file = "globalgamemanagers"
                }
            }
        }
    },

    zzz = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "nap_global",
                title = editions_locales.global,
                entries = {
                    data_folder = "ZenlessZoneZero_Data",
                    version_file = "globalgamemanagers"
                }
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "nap_cn",
                title = editions_locales.china,
                entries = {
                    data_folder = "ZenlessZoneZero_Data",
                    version_file = "globalgamemanagers"
                }
            }
        }
    },

    hsr = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "hkrpg_global",
                title = editions_locales.global,
                entries = {
                    data_folder = "StarRail_Data",
                    version_file = "globalgamemanagers"
                }
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "hkrpg_cn",
                title = editions_locales.china,
                entries = {
                    data_folder = "StarRail_Data",
                    version_file = "globalgamemanagers"
                }
            }
        }
    },

    honkai = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "bh3_global",
                title = editions_locales.global,
                entries = {
                    data_folder = "BH3_Data",
                    version_file = "globalgamemanagers"
                }
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "bh3_cn",
                title = editions_locales.china,
                entries = {
                    data_folder = "BH3_Data",
                    version_file = "globalgamemanagers"
                }
            }
        }
    }
}

-- Declared in the semver package
type Semver = { major: number, minor: number, patch: number }

type Api = {
    version: Semver,
    segments: { Segment },
    voiceovers: { Voiceover },
    extracted_url: string,
    patches: { Patch }
}

type Segment = {
    url: string,
    md5: string,
    download_size: number,
    extracted_size: number
}

type Voiceover = {
    language: string,
    url: string,
    md5: string,
    download_size: number,
    extracted_size: number
}

type Patch = {
    version: Semver,
    segments: { Segment },
    voiceovers: { Voiceover }
}

local api_cache = {}

-- Try to fetch the HYVse API.
local function api_get(url: string, id: string): Api?
    local semver = import("semver")
    local iter = import("iterable")

    if not api_cache[url] then
        local response = net.fetch(url)

        if not response.is_ok then
            error("API request failed: HTTP code " .. response.status)
        end

        api_cache[url] = str.decode(str.from_bytes(response.body), "json")
    end

    local scope = iter(api_cache[url].data.game_packages)
        .find(function(game)
            return string.find(game.game.biz, id) or string.find(game.game.id, id)
        end)

    if not scope then
        return nil
    end

    local response = clone(scope.value)

    return {
        version = semver(response.main.major.version) or error(`failed to parse semver game version from '{response.main.major.version}'`),

        segments = iter(response.main.major.game_pkgs)
            .map(function(package)
                return {
                    url = package.url,
                    md5 = package.md5,
                    download_size = package.size + 0,
                    extracted_size = package.decompressed_size + 0
                }
            end)
            .collect(),

        voiceovers = iter(response.main.major.audio_pkgs)
            .map(function(package)
                return {
                    language = package.language,
                    url = package.url,
                    md5 = package.md5,
                    download_size = package.size + 0,
                    extracted_size = package.decompressed_size + 0
                }
            end)
            .collect(),

        extracted_url = response.main.major.res_list_url,

        patches = iter(response.main.patches)
            .map(function(patch)
                return {
                    version = semver(patch.version) or error(`failed to parse semver patch version from '{patch.version}'`),

                    segments = iter(patch.game_pkgs)
                        .map(function(package)
                            return {
                                url = package.url,
                                md5 = package.md5,
                                download_size = package.size + 0,
                                extracted_size = package.decompressed_size + 0
                            }
                        end)
                        .collect(),

                    voiceovers = iter(patch.audio_pkgs)
                        .map(function(package)
                            return {
                                language = package.language,
                                url = package.url,
                                md5 = package.md5,
                                download_size = package.size + 0,
                                extracted_size = package.decompressed_size + 0
                            }
                        end)
                        .collect()
                }
            end)
            .collect()
    }
end

-- Try to parse the game version from its file.
local function parse_game_version(version_file_path: string): Semver?
    if not fs.exists(game_folder) then
        return nil
    end

    local handle = fs.open(version_file_path)

    fs.seek(handle, 4500)

    local buf = fs.read(handle, 500)

    fs.close(handle)

    local function is_digit(byte: number): boolean
        return byte >= 48 and byte <= 57
    end

    for i = 1, 496 do
        -- x.y.z
        if is_digit(buf[i]) and is_digit(buf[i + 2]) and is_digit(buf[i + 4]) and buf[i + 1] == 46 and buf[i + 3] == 46 then
            return {
                major = buf[i] - 48,
                minor = buf[i + 2] - 48,
                patch = buf[i + 4] - 48
            }
        end
    end

    return nil
end

local lib = {}

for game_name, game in pairs(games) do
    lib[game_name] = {}

    for edition_name, edition in pairs(game.editions) do
        local base_path = path.persist_dir(edition.game_id)

        dbg(base_path)

        local data_path = path.join(base_path, edition.entries.data_folder)

        dbg(data_path)

        local version_path = path.join(data_path, edition.entries.version_file)

        dbg(version_path)

        lib[game_name][edition_name] = {
            title = edition.title,

            paths = {
                base_folder = base_path,
                data_folder = data_path,
                version_file = version_path
            },

            api = {
                get = function()
                    return api_get(edition.api_url, edition.game_id)
                end
            },

            parse_version = function()
                return parse_game_version(version_path)
            end
        }
    end
end

return lib
