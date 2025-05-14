-- wuthering_waves integration v0.0.0
-- Copyright (C) 2025  Dylan Donnell <dylan.donnell@student.griffith.ie>
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

local i18n = import("i18n").i18n
local iter = import("iterable")
local jadeite = import("jadeite")

local data_dir_path: string = path.persist_dir("wuthering_waves")
local engine_configs_path = path.join(data_dir_path, "engine_configs")

-- game index URL
local function game_index(edition: string)
    if edition == "china" then
        return "https://prod-alicdn-gamestarter.kurogame.com/launcher/game/G153/50009_ZXniDENS4vnMhNEhl7cLOQMojTLKLGgu/index.json"
    end
    return "https://prod-alicdn-gamestarter.kurogame.com/launcher/game/G153/50004_obOHXFrFanqsaIEOmuKroCcbZkQRBC7c/index.json"
end

local function game_exe_path(edition: string)
    return path.join(data_dir_path, edition, "Client", "Binaries", "Win64", "Client-Win64-Shipping.exe")
end

-- read version from .version file of given edition
local function get_installed_version(edition: string): string?
    local version_file_path: string = path.join(data_dir_path, edition, ".version")

    if not fs.exists(version_file_path) then
        return nil
    end

    return str.from_bytes(fs.read_file(version_file_path))
end

-- write version to .version file of given edition
local function set_installed_version(edition: string, version: string)
    local version_file_path: string = path.join(data_dir_path, edition, ".version")
    fs.create_dir(data_dir_path)
    fs.write_file(version_file_path, str.to_bytes(version))
end

-- get resource information from index
local function get_resource_info(edition: string)
    local resp = net.fetch(game_index(edition))

    if resp.is_ok then
        -- parse index.json from response
        local body = str.decode(str.from_bytes(resp.body), "json")

        local current_version = body.default.config.version
        if not current_version then
            error(`current version not found`)
        end

        local cdn_url = nil
        if #body.default.cdnList > 0 then
            cdn_url = body.default.cdnList[1].url
        else
            error(`cdn url not found`)
        end

        -- get resources URL
        local index_file = nil
        if body.default.config.indexFile then
            index_file = cdn_url .. body.default.config.indexFile
        else
            error(`resources url not found`)
        end

        -- get resources base path
        local base_url = nil
        if body.default.config.baseUrl then
            base_url = cdn_url .. body.default.config.baseUrl
        else
            error(`resources base path not found`)
        end

        return {
            version = current_version,
            index_file = index_file,
            base_url = base_url
        }
    end

    return nil
end

-- assume game is installed if game exe path and version file exists
local function is_game_installed(edition: string): boolean
    local installed_version = get_installed_version(edition)

    if not installed_version then
        return false
    end

    return fs.exists(game_exe_path(edition))
end

local function parallel_download(files, base_url, output_dir, max_parallel, progress_callback)
    -- calculate total download size
    local total_size = iter(files).cloned().fold(0, function(acc, f)
        return acc + f.size
    end)

    -- store downloaded bytes of each file in table
    local download_progress = {}
    for i = 1, #files do
        download_progress[i] = 0
    end

    -- create shared downloader
    local downloader_handle = downloader.create()

    -- process files in chunks of max_parallel
    local i = 1
    while i <= #files do
        local active_tasks = {}

        -- start up to max_parallel downloads
        for j = i, math.min(i + max_parallel - 1, #files) do
            local file = files[j]
            local dest_path = path.join(output_dir, file.dest)

            -- skip file if exists
            if fs.exists(dest_path) then
                download_progress[j] = file.size
                progress_callback(iter(download_progress).cloned().sum(), total_size)
                continue
            end

            -- calculate file URL
            local file_url = base_url .. string.gsub(file.dest, " ", "%%20")

            -- download the file, callback with sum of downloaded file sizes
            local task_handle = downloader.download(downloader_handle, {
                url = file_url,
                output_file = dest_path,
                continue_download = true,

                on_update = function(current, _)
                    download_progress[j] = current
                    progress_callback(iter(download_progress).cloned().sum(), total_size)
                end,

                on_finish = function(total)
                    download_progress[j] = total
                    progress_callback(iter(download_progress).cloned().sum(), total_size)
                end
            })

            active_tasks[j] = task_handle
        end

        -- wait for all active downloads to complete
        for j = i, math.min(i + max_parallel - 1, #files) do
            if active_tasks[j] then
                downloader.wait(active_tasks[j])
            end
        end

        -- move to the next chunk of files
        i = i + max_parallel
    end

    downloader.close(downloader_handle)
end

-- get configs from https://github.com/AlteriaX/WuWa-Configs, return version installed
local function get_engine_config()
    local latest_version_file = path.join(engine_configs_path, ".latest")

    -- fetch tags
    local headers = {}
    headers["User-Agent"] = "curl/8.13.0"
    headers["Accept"] = "*/*"
    local tags_resp = net.fetch("https://api.github.com/repos/AlteriaX/WuWa-Configs/tags", { method = "get", headers = headers , body = {}})
    if tags_resp.is_ok then
        -- decode json
        local tags_json = str.decode(str.from_bytes(tags_resp.body), "json")
        local latest = tags_json[1]
        local name = latest["name"]

        -- if target path exists, no need to redownload
        if fs.exists(path.join(engine_configs_path, "WuWa-Configs-" .. name:gsub("v", ""))) then
            return name
        end

        local output_file = path.join(path.temp_dir(), `engine_configs_{name}.zip`)

        -- download archive
        local handle = downloader.create()
        local task = downloader.download(handle, {
            url = `https://github.com/AlteriaX/WuWa-Configs/archive/refs/tags/{name}.zip`,
            output_file = output_file,
            on_finish = function(total)
                dbg(`downloaded {total} B`)
            end
        })
        downloader.wait(task)
        downloader.close(handle)

        -- extract archive
        local arch = archive.open(output_file, "zip")
        archive.extract(arch, engine_configs_path)
        archive.close(arch)

        -- remove archive
        fs.remove(output_file)

        -- write latest version file
        fs.write_file(latest_version_file, name)

        return name
    else
        -- github isn't accessible, return the last downloaded version
        if fs.exists(latest_version_file) then
            return fs.read_file(latest_version_file)
        end
    end

    error(`no response from github api`)
    return ""
end

-- overwite the Engine.ini file with the specified config number of a given version
local function apply_engine_config(edition, version, num)
    local engine_ini_src_path = path.join(engine_configs_path, "WuWa-Configs-" .. version:gsub("v", ""), "Config " .. num, "Engine.ini")
    local engine_ini_dest_path = path.join(data_dir_path, edition, "Client", "Saved", "Config", "WindowsNoEditor", "Engine.ini")

    if fs.exists(engine_ini_src_path) then
        fs.remove(engine_ini_dest_path)
        fs.copy(engine_ini_src_path, engine_ini_dest_path)
    end
end

-- test each file against its hash, return a list of non-matching hashes
local function test_hash(files, base_dir, progress_callback)
    local results = {}
    local total_size = iter(files).cloned().fold(0, function(acc, f)
        return acc + f.size
    end)
    local current_size = 0

    for _, file in ipairs(files) do
        local dest_path = path.join(base_dir, file.dest)

        -- remove existing file if it doesn't match the hash
        if fs.exists(dest_path) then
            dbg(`Hashing file {dest_path}`)
            local result = hash.file(dest_path, "md5")

            current_size += file.size
            progress_callback(current_size, total_size)


            -- format result to lowercase md5
            local hashed = iter(result).fold("", function(acc, word) return acc .. string.format("%02x", word) end)
            hashed = string.lower(hashed)

            -- remove file if non-matching
            if hashed ~= file.md5 then
                table.insert(result, file.dest)
            end
        end
    end

    return results
end

-- settings management
local __settings = nil
local __components = nil

local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "wuthering_waves",
            layout = {
                game = {
                    title = i18n("game"),
                    entries = {
                        dx11 = {
                            title = "Use DX11",
                            description = "Run game with DirectX 11 instead of DirectX 12",
                            entry = {
                                format = "switch",
                                default = true
                            }
                        },
                        skip_splash = {
                            title = "Skip splash",
                            description = "Skip intro videos",
                            entry = {
                                format = "switch",
                                default = false
                            }
                        },
                        engine_config = {
                            title = "Alternate engine config",
                            description = "Replace Engine.ini with config from AlteriaX/WuWa-Configs",
                            entry = {
                                format = "enum",
                                default = "none",
                                values = {
                                    none = "None",
                                    c1 = "Config 1",
                                    c2 = "Config 2",
                                    c3 = "Config 3",
                                    c4 = "Config 4",
                                    c5 = "Config 5"
                                }
                            }
                        },
                        wayland = {
                            title = "Use wine wayland",
                            description = "Unset DISPLAY so wine wayland is used by default",
                            entry = {
                                format = "switch",
                                default = false
                            }
                        }
                    }
                },
                download = {
                    title = i18n("download"),
                    entries = {
                        max_parallel = {
                            title = "Max parallel downloads",
                            description = "Maximum number of downloads to run in parallel",
                            entry = {
                                format = "text",
                                default = "8"
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
            game = "wuthering_waves",
            settings = {
                get_property = settings.get_property,
                set_property = settings.set_property
            }
        })
    end

    return __components
end

return {
    standard = 1,

    editions = function(platform: string)
        return {
            { name = "global", title = i18n("global_game_edition") },
            { name = "china",  title = i18n("china_game_edition")  }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            local components = import_components()
            local status = components.game.get_status(variant)

            if status then
                return status
            end

            if not is_game_installed(variant.edition) then
                return "not-installed"
            end

            -- check if there's a newer version available
            local resource_info = get_resource_info(variant.edition)
            local installed_version = get_installed_version(variant.edition)

            if installed_version and resource_info.version and installed_version ~= resource_info.version then
                return "update-required"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            local components = import_components()
            local diff = components.game.get_diff(variant)

            if diff then
                return diff
            end

            -- check if there's an update
            local resource_info = get_resource_info(variant.edition)
            local installed_version = get_installed_version(variant.edition)

            -- get indexFile.json
            local index_file_resp = net.fetch(resource_info.index_file)
            if not index_file_resp.is_ok then
                error(`could not fetch indexFile.json`)
                return
            end
            local index_file_data = str.decode(str.from_bytes(index_file_resp.body), "json")

            local output_dir = path.join(data_dir_path, variant.edition)

            -- get max parallel setting
            local settings = import_settings()
            local concurrent_downloads = tonumber(settings.get_property("download.max_parallel"))

            if is_game_installed(variant.edition) then
                if installed_version and resource_info.version and installed_version ~= resource_info.version then
                    return {
                        title = i18n("update_game"),
                        description = i18n("update_game_description", {
                            current = installed_version,
                            new = resource_info.version
                        }),
                        pipeline = {
                            {
                                title = "Cleaning outdated files",
                                perform = function(updater)
                                    fs.remove(output_dir)
                                end
                            },
                            {
                                title = i18n("download_game_files"),
                                perform = function(updater)
                                    -- start parallel download
                                    parallel_download(
                                        index_file_data.resource,
                                        resource_info.base_url,
                                        output_dir,
                                        concurrent_downloads,
                                        function(current, total)
                                            updater({
                                                title = i18n("downloading_game_files"),
                                                progress = {
                                                    current = current,
                                                    total = total,
                                                    format = function()
                                                        -- convert to gb for display
                                                        local current_gb = math.floor((current / 1000 / 1000 / 1000) * 10) / 10
                                                        local total_gb = math.floor((total / 1000 / 1000 / 1000) * 10) / 10
                                                        local percentage = math.floor((current / total) * 100)

                                                        return i18n("downloading_progress", {
                                                            current = current_gb,
                                                            total = total_gb,
                                                            percentage = percentage
                                                        })
                                                    end
                                                }
                                            })
                                        end
                                    )

                                    -- save version
                                    set_installed_version(variant.edition, resource_info.version)
                                end
                            },
                            {
                                title = "Verifying files",
                                perform = function(updater)
                                    while true do
                                        -- get hash result
                                        local hash_result = test_hash(index_file_data.resource, output_dir, function(current_size, total_size)
                                            updater({
                                                title = "Calculating file hash",
                                                progress = {
                                                current = current_size,
                                                total = total_size,
                                                format = function()
                                                    local current_gb = math.floor((current_size / 1000 / 1000 / 1000) * 10) / 10
                                                    local total_gb = math.floor((total_size / 1000 / 1000 / 1000) * 10) / 10
                                                    local percentage = math.floor((current_size / total_size) * 100)

                                                    return "Processed " .. current_gb .. " GB of " .. total_gb .. " GB - " .. percentage .. "%"
                                                end
                                            }
                                        })
                                        end)

                                        -- no corrupted files
                                        if #hash_result == 0 then
                                            break
                                        end

                                        -- remove corrupted files
                                        for _, file in hash_result do
                                            fs.remove(path.join(output_dir, file))
                                        end

                                        -- redownload corrupted files
                                        parallel_download(
                                            hash_result,
                                            resource_info.base_url,
                                            output_dir,
                                            concurrent_downloads,
                                            function(current, total)
                                                updater({
                                                    title = i18n("downloading_game_files"),
                                                    progress = {
                                                        current = current,
                                                        total = total,
                                                        format = function()
                                                            -- convert to gb for display
                                                            local current_gb = math.floor((current / 1000 / 1000 / 1000) * 10) / 10
                                                            local total_gb = math.floor((total / 1000 / 1000 / 1000) * 10) / 10
                                                            local percentage = math.floor((current / total) * 100)

                                                            return i18n("downloading_progress", {
                                                                current = current_gb,
                                                                total = total_gb,
                                                                percentage = percentage
                                                            })
                                                        end
                                                    }
                                                })
                                            end
                                        )
                                    end
                                end
                            }
                        }
                    }
                end

                return nil
            end

            -- fresh installation
            return {
                title = i18n("install_game"),
                description = i18n("install_game_description", {
                    version = resource_info.version
                }),

                pipeline = {
                    {
                        title = i18n("download_game_files"),

                        perform = function(updater)
                            -- start parallel download
                            parallel_download(
                                index_file_data.resource,
                                resource_info.base_url,
                                output_dir,
                                concurrent_downloads,
                                function(current, total)
                                    updater({
                                        title = i18n("downloading_game_files"),
                                        progress = {
                                            current = current,
                                            total = total,
                                            format = function()
                                                -- Convert to GB for display
                                                local current_gb = math.floor((current / 1000 / 1000 / 1000) * 10) / 10
                                                local total_gb = math.floor((total / 1000 / 1000 / 1000) * 10) / 10
                                                local percentage = math.floor((current / total) * 100)

                                                return i18n("downloading_progress", {
                                                    current = current_gb,
                                                    total = total_gb,
                                                    percentage = percentage
                                                })
                                            end
                                        }
                                    })
                                end
                            )

                            -- save version
                            set_installed_version(variant.edition, resource_info.version)
                        end
                    }
                }
            }
        end,

        get_launch_info = function(variant: Variant)
            if not is_game_installed(variant.edition) then
                return {
                    status = "disabled",
                    hint = i18n("game_not_installed"),
                    binary = ""
                }
            end

            local settings = import_settings()

            -- overwrite engine config if specified
            local use_engine_config = settings.get_property("game.engine_config")
            if use_engine_config ~= "none" then
                local engine_config = get_engine_config()
                apply_engine_config(variant.edition, engine_config, use_engine_config:gsub("c", ""))
            end

            -- add -dx11 or -dx12 arg if specified in settings
            local args = {}
            local use_dx11 = settings.get_property("game.dx11")

            if use_dx11 then
                table.insert(args, "-dx11")
            else
                table.insert(args, "-dx12")
            end

            -- add -SkipSplash if specified in settings
            local skip_splash = settings.get_property("game.skip_splash")

            if skip_splash then
                table.insert(args, "-SkipSplash")
            end

            -- add empty DISPLAY envvar if specified in settings
            -- first overrides are for dxvk, second is to disable popup window
            local env = { WINEDLLOVERRIDES = "d3d8,d3d9,d3d10core,d3d11,dxgi=n;KRSDKExternal.exe=d" }
            local use_wayland = settings.get_property("game.wayland")

            if use_wayland then
                env["DISPLAY"] = ""
            end

            -- run game
            local components = import_components()
            return components.game.wrap_launch_info(jadeite.wrap_launch_command({
                status = "normal",
                binary = game_exe_path(variant.edition),
                args = args,
                env = env
            }))
        end
    },

    settings = {
        get_property = function(name: string)
            local settings = import_settings()
            return settings.get_property(name)
        end,

        set_property = function(name: string, value: any)
            local settings = import_settings()
            settings.set_property(name, value)
        end,

        get_layout = function(variant: Variant)
            local settings = import_settings()
            local components = import_components()

            return iter(settings.get_layout(variant))
                .chain(components.settings.get_layout())
                .collect()
        end
    }
}
