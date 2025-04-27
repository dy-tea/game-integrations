-- wuthering_waves integration v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>, Dylan Donnell <dylan.donnell@student.griffith.ie>
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

-- Helper functions to get game data URLs
local function game_index(edition: string)
    if edition == "china" then
        return "https://prod-alicdn-gamestarter.kurogame.com/pcstarter/prod/game/G153/50009_ZXniDENS4vnMhNEhl7cLOQMojTLKLGgu/index.json"
    end
    return "https://prod-alicdn-gamestarter.kurogame.com/pcstarter/prod/game/G153/50004_obOHXFrFanqsaIEOmuKroCcbZkQRBC7c/index.json"
end

local function game_exe_path(edition: string)
    return path.join(data_dir_path, edition, "Client", "Binaries", "Win64", "Client-Win64-Shipping.exe")
end

-- Get installed version
local function get_installed_version(edition: string): string?
    local version_file_path: string = path.join(data_dir_path, edition, ".version")

    if not fs.exists(version_file_path) then
        return nil
    end

    return str.from_bytes(fs.read_file(version_file_path))
end

-- Set installed version
local function set_installed_version(edition: string, version: string)
    local version_file_path: string = path.join(data_dir_path, edition, ".version")
    fs.create_dir(data_dir_path)
    fs.write_file(version_file_path, str.to_bytes(version))
end

-- Get resource information from index
local function get_resource_info(edition: string)
    local temp_dir = path.temp_dir()
    local index_file = path.join(temp_dir, "wuthering_waves_index.json")

    -- Download index.json
    local downloader_handle = downloader.create()
    local task_handle = downloader.download(downloader_handle, {
        url = game_index(edition),
        output_file = index_file
    })

    downloader.wait(task_handle)
    downloader.close(downloader_handle)

    -- Parse index.json
    local index_content = fs.read_file(index_file)
    local index_data = str.decode(str.from_bytes(index_content), "json")

    local current_version = index_data.default.version
    local resources_url = nil
    local cdn_url = nil

    -- Get the first CDN URL
    if #index_data.default.cdnList > 0 then
        cdn_url = index_data.default.cdnList[1].url
    end

    -- Get resources URL
    if index_data.default.resources then
        resources_url = cdn_url .. index_data.default.resources
    end

    -- Get resources base path
    local resources_base_path = nil
    if index_data.default.resourcesBasePath then
        resources_base_path = cdn_url .. index_data.default.resourcesBasePath
    end

    fs.remove(index_file)

    return {
        version = current_version,
        resources_url = resources_url,
        resources_base_path = resources_base_path
    }
end

-- Check if the game is installed
local function is_game_installed(edition: string): boolean
    local installed_version = get_installed_version(edition)

    if not installed_version then
        return false
    end

    return fs.exists(game_exe_path(edition))
end

-- FIXME current total size is broken
local function parallel_download(files, base_url, output_dir, max_parallel, progress_callback)
    -- Calculate total download size
    local total_size = iter(files).cloned().fold(0, function(acc, f)
        return acc + f.size
    end)

    -- Track downloaded bytes across all files
    local download_progress = {}
    for i = 1, #files do
        download_progress[i] = 0
    end

    -- Create shared downloader
    local downloader_handle = downloader.create()

    -- Process files in chunks of max_parallel
    local i = 1
    while i <= #files do
        local active_tasks = {}

        -- Start up to max_parallel downloads
        for j = i, math.min(i + max_parallel - 1, #files) do
            local file = files[j]
            local dest_path = path.join(output_dir, file.dest)

            -- Calculate file URL
            local file_url = base_url .. file.dest

            -- Download the file
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

        -- Wait for all active downloads to complete
        for j = i, math.min(i + max_parallel - 1, #files) do
            downloader.wait(active_tasks[j])
        end

        -- Move to the next chunk of files
        i = i + max_parallel
    end

    downloader.close(downloader_handle)
end

-- Settings management
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

            -- Check if there's a newer version available
            local resource_info = get_resource_info(variant.edition)
            local installed_version = get_installed_version(variant.edition)

            dbg(resource_info)
            dbg(installed_version)

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

            -- Check if there's an update
            local resource_info = get_resource_info(variant.edition)
            local installed_version = get_installed_version(variant.edition)

            local temp_dir = path.temp_dir()
            local resource_json_path = path.join(temp_dir, "wuthering_waves_resource.json")

            -- Download resource.json
            local downloader_handle = downloader.create()
            local task_handle = downloader.download(downloader_handle, {
                url = resource_info.resources_url,
                output_file = resource_json_path,
            })

            downloader.wait(task_handle)
            downloader.close(downloader_handle)

            -- Parse resource.json
            local resource_content = fs.read_file(resource_json_path)
            local resource_data = str.decode(str.from_bytes(resource_content), "json")

            fs.remove(resource_json_path)

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
                                title = "Calculating diff",
                                perform = function(updater)
                                    local total_size = iter(resource_data.resource).cloned().fold(0, function(acc, f)
                                        return acc + f.size
                                    end)
                                    local current_size = 0

                                    for _, file in ipairs(resource_data.resource) do
                                        local dest_path = path.join(output_dir, file.dest)

                                        -- Remove existing file if it doesn't match the hash
                                        if fs.exists(dest_path) then
                                            local file_handle = fs.open(dest_path)

                                            dbg(`hashing {dest_path}`)

                                            local hasher = hash.builder("md5")

                                            local chunk = fs.read(file_handle)
                                            while #chunk > 0 do
                                                hash.write(hasher, chunk)
                                                current_size += #chunk

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

                                                chunk = fs.read(file_handle)
                                            end

                                            if hash.finalize(hasher) ~= file.hash then
                                                dbg(`hash mismatch, removing file`)
                                                fs.remove(dest_path)
                                            end

                                            fs.close(file_handle)
                                        else
                                            -- File already exists, skip it
                                            current_size += file.size
                                        end
                                    end
                                end
                            },
                            {
                                title = i18n("download_game_files"),
                                perform = function(updater)
                                    -- start parallel download
                                    parallel_download(
                                        resource_data.resource,
                                        resource_info.resources_base_path,
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

                                    -- Update version
                                    set_installed_version(variant.edition, resource_info.version)
                                end
                            }
                        }
                    }
                end

                return nil
            end

            -- Fresh installation
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
                                resource_data.resource,
                                resource_info.resources_base_path,
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

                            -- Save version
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

            local args = {}
            local settings = import_settings()
            local use_dx11 = settings.get_property("game.dx11")

            if use_dx11 then
                table.insert(args, "-dx11")
            end

            local components = import_components()

            return components.game.wrap_launch_info(jadeite.wrap_launch_command({
                status = "normal",
                binary = game_exe_path(variant.edition),
                args = args
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
