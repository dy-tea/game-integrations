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

local semver = import("semver")
local iter = import("iterable")
local i18n = import("i18n").i18n

-- Declared in semver
type Semver = { major: number, minor: number, patch: number }

----------------------------------------
-- API integration

-- The ["china"] url will be used if edition == "china",
-- ["global"] will be used for all other editions.
local api_urls = {
    global = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/%s?launcher_id=VYTpXlbWo8",
    china = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/%s?launcher_id=jGHBHlcOq1"
}

local function get_api_url(endpoint: string, edition: string): string
    local api_url = if edition == "china" then api_urls.china else api_urls.global

    return api_url:format(endpoint)
end

-- All the global HI3 editions have the same biz,
-- so it's easier to just use id everywhere.
local games = {
    ["gopR6Cufr3"] = { name = "genshin", edition = "global" },
    ["1Z8W5NHUQb"] = { name = "genshin", edition = "china" },

    ["4ziysqXOQ8"] = { name = "hsr", edition = "global" },
    ["64kMb5iAWu"] = { name = "hsr", edition = "china" },

    ["U5hbdsT9W7"] = { name = "zzz", edition = "global" },
    ["x6znKlJ0xK"] = { name = "zzz", edition = "china" },

    ["5TIVvvcwtM"] = { name = "hi3", edition = "global" },
    ["wkE5P5WsIf"] = { name = "hi3", edition = "taiwan" },
    ["osvnlOc0S8"] = { name = "hi3", edition = "china" },
    ["g0mMIvshDb"] = { name = "hi3", edition = "japan" },
    ["uxB4MC7nzC"] = { name = "hi3", edition = "korea" },
    ["bxPTXSET5t"] = { name = "hi3", edition = "sea" }
}

-- The following abomination maintains a parsed cache of all API endpoint responses.
-- You should be careful to not modify the return value, as it is not cloned.

type ApiFetchOptions = {
    game: string,
    edition: string,

    endpoint: string,
    field: string,

    required: boolean,

    parse_fn: (table) -> table
}

local api_cache = {}

local function fetch_api(options: ApiFetchOptions): table
    if not api_cache[options.endpoint] then
        api_cache[options.endpoint] = {}
    end
    local endpoint_cache = api_cache[options.endpoint]

    -- The actual edition entry will be nil/{} even if we don't find the game.
    if not endpoint_cache[options.game] then
        endpoint_cache[options.game] = {}
    end
    local game_cache = endpoint_cache[options.game]

    if not game_cache[options.edition] then
        local api_url = get_api_url(options.endpoint, options.edition)

        local response = net.fetch(api_url)
        if not response.is_ok then
            error("API request failed: HTTP code " .. response.status)
        end
        local response_json = str.decode(str.from_bytes(response.body), "json")

        for _, entry in response_json.data[options.field] do
            local game_def = games[entry.game.id]

            if game_def then
                if not endpoint_cache[game_def.name] then
                    endpoint_cache[game_def.name] = {}
                end

                endpoint_cache[game_def.name][game_def.edition] = options.parse_fn(entry)
            else
                dbg(`{options.endpoint} fetch skipping game with id='{entry.game.id}' biz='{entry.game.biz}'`)
            end
        end

        if not game_cache[options.edition] then
            if options.required then
                error(`Failed to find game '{options.game}:{options.edition}' in {options.endpoint} response`)
            else
                -- Empty table will both prevent future requests and serve as a default value.
                game_cache[options.edition] = {}
            end
        end
    end

    return game_cache[options.edition]
end

---------------------------------------
-- Game packages API

-- "uncompressed_size" here is the size of the files themselves, excluding the archive.
-- Sum of compressed+uncompressed complicates things if the archive and game are on
-- different partitions, so they are manually separated by the script.
type Package = {
    url: string,
    md5: string,
    filename: string,
    compressed_size: number,
    uncompressed_size: number
}

type AudioPackage = {
    language: string,
    package: Package
}

type PackageList = {
    version: Semver,
    game_packages: { Package },
    audio_packages: { AudioPackage },
    uncompressed_url: string
}

type VersionPackages = {
    full: PackageList,
    patches: { PackageList }
}

type GamePackages = {
    main: VersionPackages,
    predownload: VersionPackages?
}

local function parse_package(response: table): Package
    local compressed_size = tonumber(response.size)

    return {
        url = response.url,
        md5 = response.md5,
        filename = response.url:gmatch("[^/]*$")(),
        compressed_size = compressed_size,
        uncompressed_size = tonumber(response.decompressed_size) - compressed_size
    }
end

local function parse_packages(response: table): { Package }
    local packages = iter(response)
        .map(parse_package)
        .collect()

    if #packages > 0 then
        -- Include a unique hash in every filename to avoid collisions, because 
        -- some audio packages have amazing names like "English.7z" without 
        -- any indication of the game version. 
        local package_md5s = iter(packages)
            .cloned()
            .map(function(package) return package.md5 end)
            .fold("", function(acc, md5) return acc .. md5 end)

        local package_md5s_hash = hash.calc(str.decode(package_md5s, "base16"), "seahash")
        local hash_str = str.encode(package_md5s_hash, "base32/hex-nopad")

        for _, package in packages do
            -- They are probably never going to use any other archive format...
            package.filename = package.filename:gsub("%.7z", `.{hash_str}.7z`)
            package.filename = package.filename:gsub("%.zip", `.{hash_str}.zip`)
        end
    end

    return packages
end

local function parse_package_list(response: table): PackageList
    return {
        version = semver(response.version),

        game_packages = parse_packages(response.game_pkgs),

        audio_packages = iter(response.audio_pkgs)
            .map(function(response)
                return {
                    language = response.language,
                    package = parse_packages({ response })[1]
                }
            end)
            .collect(),

        uncompressed_url = response.res_list_url
    }
end

local function parse_version_packages(response: table): VersionPackages
    if not response.major then
        return nil
    end

    return {
        full = parse_package_list(response.major),

        patches = iter(response.patches)
            .map(parse_package_list)
            .collect()
    }
end

local function fetch_packages(game: string, edition: string): GamePackages
    return fetch_api({
        game = game,
        edition = edition,

        endpoint = "getGamePackages",
        field = "game_packages",

        required = true,

        parse_fn = function(entry)
            return {
                main = parse_version_packages(entry.main),
                predownload = parse_version_packages(entry.pre_download)
            }
        end
    })
end

---------------------------------------
-- Game configs API

-- Returns a lot more stuff, we don't need most of it.
type GameConfigs = {
    exe_name: string,

    audio_package_path: string
}

local function fetch_configs(game: string, edition: string): GameConfigs
    return fetch_api({
        game = game,
        edition = edition,

        endpoint = "getGameConfigs",
        field = "launch_configs",

        required = true,

        parse_fn = function(entry)
            return {
                exe_name = entry.exe_file_name,

                audio_package_path = entry.audio_pkg_res_dir
            }
        end
    })
end

---------------------------------------
-- Game deprecated file configs API

-- Returns a list of files that *must* be deleted.
-- The game may refuse to start with anticheat errors if they are present.
--
-- Currently only used in Genshin, entries for other games completely absent.

local function fetch_deprecated_files(game: string, edition: string): { string }
    return fetch_api({
        game = game,
        edition = edition,

        endpoint = "getGameDeprecatedFileConfigs",
        field = "deprecated_file_configs",

        required = false,

        parse_fn = function(entry)
            return iter(entry.deprecated_files)
                .map(function(file) return file.name end)
                .collect()
        end
    })
end

---------------------------------------
-- Game version management

type InstalledVersion = {
    game: Semver,
    audio: { [string]: Semver }?
}

local function read_version_file(version_file: string): InstalledVersion?
    if not fs.exists(version_file) then
        return nil
    end

    local version_data = str.decode(str.from_bytes(fs.read_file(version_file)), "toml")

    local version = {
        game = semver(version_data.game)
    }

    if version_data.audio then
        version.audio = {}

        for language, audio_version_data in version_data.audio do
            version.audio[language] = semver(audio_version_data)
        end
    end

    return version
end

local function write_version_file(version_file: string, version: InstalledVersion)
    local version_data = {
        game = tostring(version.game)
    }

    if version.audio then
        version_data.audio = {}

        for language, audio_version in version.audio do
            version_data.audio[language] = tostring(audio_version)
        end
    end

    fs.write_file(version_file, str.encode(version_data, "toml"))
end

---------------------------------------
-- Game package pipeline actions

local function make_download_action(packages: { Package }, temp_folder: string)
    return {
        perform = function(updater)
            local total_bytes = iter(packages)
                .cloned()
                .map(function(package) return package.compressed_size end)
                .sum()

            local current_bytes = 0

            local downloader_handle = downloader.create()

            for _, package in packages do
                local archive_path = path.join(temp_folder, package.filename)

                local task_handle = downloader.download(downloader_handle, {
                    url = package.url,
                    output_file = archive_path,
                    continue_download = true,

                    on_update = function(current, total)
                        local current_total = current_bytes + current

                        updater({
                            progress = {
                                current = current_total,
                                
                                total = total_bytes,

                                format = function()
                                    return i18n("downloading_progress", {
                                        current = string.format("%.2f", current_total / 1024 / 1024 / 1024),
                                        total = string.format("%.2f", total_bytes / 1024 / 1024 / 1024)
                                    })
                                end
                            }
                        })
                    end
                })

                downloader.wait(task_handle)
                
                local real_length = fs.metadata(archive_path).length

                if real_length > package.compressed_size then
                    -- Sometimes, the archives will have random trash at the end for unknown reasons.
                    -- Remove it manually for now.
                    dbg(`{package.filename} is longer than expected, truncating`)

                    local file_handle = fs.open(archive_path, { write = true })

                    fs.truncate(file_handle, package.compressed_size)

                    fs.close(file_handle)
                elseif real_length < package.compressed_size then
                    error(`{package.filename} size mismatch, should be {package.compressed_size}, is {real_length}`)
                end

                current_bytes = current_bytes + package.compressed_size
            end

            downloader.close(downloader_handle)
        end
    }
end

local function make_unpack_action(packages: { Package }, temp_folder: string, target_folder: string)
    return {
        perform = function(updater)
            local handle = archive.open(path.join(temp_folder, packages[1].filename))

            local success = archive.extract(handle, target_folder, function(current, total, diff)
                updater({
                    progress = {
                        current = current,

                        total = total,

                        format = function()
                            return i18n("extraction_progress", {
                                current = string.format("%.2f", current / 1024 / 1024 / 1024),
                                total = string.format("%.2f", total / 1024 / 1024 / 1024)
                            })
                        end
                    }
                })
            end)

            archive.close(handle)

            if not success then
                error("Failed to unpack archives")
            end

            -- FIXME: not deleting the archives for testing purposes
        end
    }
end

---------------------------------------
-- Update pipeline

local function should_update(current_version: Semver?, packages: VersionPackages): boolean
    return not current_version or current_version < packages.full.version
end

type PartialPipelineOptions = {
    current_version: InstalledVersion?,

    packages: VersionPackages,
    temp_folder: string,

    -- If nil, only download without installing.
    game_folder: string?,

    -- If nil, then install game. Else install selected audio package.
    audio_language: string?
}

local function make_partial_pipeline(options: PartialPipelineOptions)
    local patch = nil
    
    if options.current_version then
        local search_version = nil

        if options.audio_language then
            search_version = options.current_version.audio[options.audio_language]
        else
            search_version = options.current_version.game
        end

        if search_version then
            patch = iter(options.packages.patches)
                .cloned()
                .find(function(patch) return patch.version == search_version end)

            if patch then
                patch = patch.value
            end
        end
    end

    local package_list = patch or options.packages.full
    local to_download = nil

    if options.audio_language then
        local audio = iter(package_list.audio_packages)
            .cloned()
            .find(function(audio) return audio.language == options.audio_language end)

        if not audio then
            error(`Failed to find audio package '{language}' in API response`)
        end

        to_download = { audio.value.package }
    else
        to_download = package_list.game_packages
    end

    local download_action = make_download_action(to_download, options.temp_folder)
    download_action.title = if options.audio_language 
        then i18n("download_audio", { language = options.audio_language }) 
        else i18n("download_game_files")

    local pipeline = {
        download_action
    }

    if options.game_folder then
        local unpack_action = make_unpack_action(to_download, options.temp_folder, options.game_folder)
        unpack_action.title = if options.audio_language 
            then i18n("extract_audio", { language = options.audio_language }) 
            else i18n("extract_game_files")

        table.insert(pipeline, unpack_action)

        if patch then
            dbg(patch)
            error("Delta updates not supported yet")
        end
    end

    return pipeline
end

---------------------------------------
-- Public interface

return function(game: string)
    return function(edition: string)
        return {
            get_main_version = function(): Semver
                return clone(fetch_packages(game, edition).main.full.version)
            end,

            get_predownload_version = function(): Semver?
                local packages = fetch_packages(game, edition)

                if packages.predownload then
                    return clone(packages.predownload.full.version)
                else
                    return nil
                end
            end,

            open_game_folder = function(game_folder: string)
                local version_file = path.join(game_folder, "version.toml")
                local installation_state_file = path.join(game_folder, "is_installing")

                return {
                    get_installed_version = function(self): InstalledVersion?
                        return read_version_file(version_file)
                    end,

                    set_installed_version = function(self, version: InstalledVersion)
                        write_version_file(version_file, version)
                    end,

                    get_exe_path = function(self)
                        return path.join(game_folder, fetch_configs(game, edition).exe_name)
                    end,

                    get_audio_package_path = function(self)
                        return path.join(game_folder, fetch_configs(game, edition).audio_package_path)
                    end,

                    is_installed = function(self)
                        if fs.exists(installation_state_file) then
                            return false
                        end

                        return fs.exists(self:get_exe_path())
                    end,

                    is_update_required = function(self, enabled_audio: { string }?)
                        local packages = fetch_packages(game, edition)

                        local current_version = self:get_installed_version() 

                        if should_update(current_version.game, packages.main) then
                            return true
                        end

                        if enabled_audio then
                            for _, language in enabled_audio do
                                if should_update(current_version.audio[language], packages.main) then
                                    return true
                                end
                            end
                        end

                        return false
                    end,

                    make_update_diff = function(self, temp_folder: string, enabled_audio: { string }?)
                        local packages = fetch_packages(game, edition)

                        local pipeline = {}

                        local current_version = self:get_installed_version() or {}
                        local installing = not self:is_installed()

                        -- Create an "is_installing" file to mark that installation has not yet completed.
                        -- This is necessary to resume installation in case the game exe was already 
                        -- unpacked, but the version file was not yet created.
                        if installing then
                            table.insert(pipeline, {
                                title = i18n("begin_installation"),

                                perform = function(updater)
                                    fs.create_file(installation_state_file)
                                end
                            })
                        end

                        if enabled_audio and not current_version.audio then
                            current_version.audio = {}     
                        end

                        if should_update(current_version.game, packages.main) then
                            pipeline = iter(pipeline)
                                .chain(make_partial_pipeline({
                                    current_version = current_version,

                                    packages = packages.main,
                                    temp_folder = temp_folder,

                                    game_folder = game_folder
                                }))
                                .collect()

                            table.insert(pipeline, {
                                title = i18n("finish_game_installation"),
                                
                                perform = function()
                                    current_version.game = packages.main.full.version

                                    self:set_installed_version(current_version)
                                end
                            })
                        end

                        if enabled_audio then
                            for _, language in enabled_audio do
                                if should_update(current_version.audio[language], packages.main) then
                                    pipeline = iter(pipeline)
                                        .chain(make_partial_pipeline({
                                            current_version = current_version,
        
                                            packages = packages.main,
                                            temp_folder = temp_folder,
        
                                            game_folder = game_folder,

                                            audio_language = language
                                        }))
                                        .collect()

                                    table.insert(pipeline, {
                                        title = i18n("finish_audio_installation", { language = language }),

                                        perform = function()
                                            current_version.audio[language] = packages.main.full.version
            
                                            self:set_installed_version(current_version)
                                        end
                                    })
                                end
                            end
                        end

                        local diff = {
                            pipeline = pipeline
                        }

                        if installing then
                            table.insert(diff.pipeline, {
                                title = i18n("finish_installation"),
                                
                                perform = function(updater)
                                    fs.remove_file(installation_state_file)
                                end
                            })

                            diff.title = i18n("install_game")
                        else
                            diff.title = i18n("update_game")
                        end

                        return diff
                    end,

                    find_deprecated_files = function(self)
                        return iter(fetch_deprecated_files(game, edition))
                            .cloned()
                            .map(function(file) return path.join(game_folder, file) end)
                            .filter(function(file) return fs.exists(file) end)
                            .collect()
                    end
                }
            end
        }
    end
end
